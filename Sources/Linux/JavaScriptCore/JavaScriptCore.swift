import Foundation
import CJavaScriptCore

// Linux stand-in for the slice of JavaScriptCore's Objective-C API that upstream uses (the WMP
// skin script bridge), built on the C API that WebKitGTK's JavaScriptCore exports. Swift values
// cross as in Apple's bridge: nil → undefined, NSNull → null, Bool, numbers, strings, arrays,
// dictionaries, JSValue, and Swift closures of the shapes upstream installs → JS functions
// (`@convention(block)` is stripped from upstream sources here; there are no ObjC blocks).
//
// ponytail: only the closure shapes upstream passes are recognised (see `JSFunctionBox.make`);
// add a case when a new one appears.

public final class JSVirtualMachine {
    let group: JSContextGroupRef
    public init() { group = JSContextGroupCreate() }
    deinit { JSContextGroupRelease(group) }
}

public final class JSContext {
    public let virtualMachine: JSVirtualMachine
    public let jsGlobalContextRef: JSGlobalContextRef
    public var exception: JSValue?
    public var exceptionHandler: ((JSContext?, JSValue?) -> Void)?
    public var name: String?

    public init?(virtualMachine: JSVirtualMachine) {
        self.virtualMachine = virtualMachine
        guard let ref = JSGlobalContextCreateInGroup(virtualMachine.group, nil) else { return nil }
        jsGlobalContextRef = ref
        exceptionHandler = { context, exception in context?.exception = exception }
        Self.registry[Int(bitPattern: ref)] = Weak(self)
    }

    public convenience init?() { self.init(virtualMachine: JSVirtualMachine()) }

    deinit {
        Self.registry[Int(bitPattern: jsGlobalContextRef)] = nil
        JSGlobalContextRelease(jsGlobalContextRef)
    }

    var ref: JSContextRef { jsGlobalContextRef }

    // MARK: Current context (inside a Swift function called from JS)

    private struct Weak { weak var context: JSContext?; init(_ c: JSContext) { context = c } }
    nonisolated(unsafe) private static var registry: [Int: Weak] = [:]
    private static let currentKey = "VoidplayJSContextStack"

    static func context(for ref: JSContextRef?) -> JSContext? {
        guard let ref else { return nil }
        return registry[Int(bitPattern: JSContextGetGlobalContext(ref))]?.context
    }

    /// The context whose JS is calling into Swift right now, on this thread.
    public static func current() -> JSContext? {
        (Thread.current.threadDictionary[currentKey] as? [JSContext])?.last
    }

    static func withCurrent<T>(_ context: JSContext, _ body: () -> T) -> T {
        var stack = Thread.current.threadDictionary[currentKey] as? [JSContext] ?? []
        stack.append(context)
        Thread.current.threadDictionary[currentKey] = stack
        defer {
            stack.removeLast()
            Thread.current.threadDictionary[currentKey] = stack
        }
        return body()
    }

    // MARK: Scripts and globals

    @discardableResult
    public func evaluateScript(_ script: String) -> JSValue? { evaluateScript(script, withSourceURL: nil) }

    @discardableResult
    public func evaluateScript(_ script: String, withSourceURL url: URL?) -> JSValue? {
        let source = JSStringCreateWithUTF8CString(script)
        defer { JSStringRelease(source) }
        let sourceURL = url.flatMap { JSStringCreateWithUTF8CString($0.absoluteString) }
        defer { if let sourceURL { JSStringRelease(sourceURL) } }
        var thrown: JSValueRef?
        let result = JSEvaluateScript(ref, source, nil, sourceURL, 1, &thrown)
        if let thrown {
            report(JSValue(ref: thrown, in: self))
            return JSValue(undefinedIn: self)
        }
        return result.map { JSValue(ref: $0, in: self) } ?? JSValue(undefinedIn: self)
    }

    func report(_ exception: JSValue) {
        if let handler = exceptionHandler { handler(self, exception) } else { self.exception = exception }
    }

    public var globalObject: JSValue { JSValue(ref: JSContextGetGlobalObject(ref), in: self) }

    public func objectForKeyedSubscript(_ key: Any) -> JSValue! { globalObject.forProperty("\(key)") }

    public func setObject(_ object: Any?, forKeyedSubscript key: Any) {
        globalObject.setValue(object, forProperty: "\(key)")
    }
}

public final class JSValue {
    public let context: JSContext
    let ref: JSValueRef

    init(ref: JSValueRef, in context: JSContext) {
        self.context = context
        self.ref = ref
        JSValueProtect(context.ref, ref)
    }

    deinit { JSValueUnprotect(context.ref, ref) }

    convenience init(undefinedIn context: JSContext) { self.init(ref: JSValueMakeUndefined(context.ref), in: context) }

    public convenience init?(object: Any?, in context: JSContext) {
        self.init(ref: JSValue.make(object, in: context), in: context)
    }

    public convenience init(newErrorFromMessage message: String, in context: JSContext) {
        let text = JSValue.make(message, in: context)
        var arguments: [JSValueRef?] = [text]
        let error = JSObjectMakeError(context.ref, 1, &arguments, nil)
        self.init(ref: error ?? JSValueMakeUndefined(context.ref), in: context)
    }

    public convenience init(nullIn context: JSContext) { self.init(ref: JSValueMakeNull(context.ref), in: context) }
    public convenience init(bool: Bool, in context: JSContext) { self.init(ref: JSValueMakeBoolean(context.ref, bool), in: context) }
    public convenience init(double: Double, in context: JSContext) { self.init(ref: JSValueMakeNumber(context.ref, double), in: context) }

    // MARK: Type tests

    public var isUndefined: Bool { JSValueIsUndefined(context.ref, ref) }
    public var isNull: Bool { JSValueIsNull(context.ref, ref) }
    public var isBoolean: Bool { JSValueIsBoolean(context.ref, ref) }
    public var isNumber: Bool { JSValueIsNumber(context.ref, ref) }
    public var isString: Bool { JSValueIsString(context.ref, ref) }
    public var isObject: Bool { JSValueIsObject(context.ref, ref) }
    public var isArray: Bool { JSValueIsArray(context.ref, ref) }

    // MARK: Conversions

    public func toBool() -> Bool { JSValueToBoolean(context.ref, ref) }
    public func toDouble() -> Double { JSValueToNumber(context.ref, ref, nil) }
    public func toInt32() -> Int32 {
        let number = toDouble()
        guard number.isFinite else { return 0 }
        return Int32(truncatingIfNeeded: Int64(number.truncatingRemainder(dividingBy: 4_294_967_296)))
    }
    public func toUInt32() -> UInt32 { UInt32(bitPattern: toInt32()) }
    public func toNumber() -> NSNumber? { NSNumber(value: toDouble()) }

    public func toString() -> String! {
        guard let string = JSValueToStringCopy(context.ref, ref, nil) else { return nil }
        defer { JSStringRelease(string) }
        return JSValue.swiftString(string)
    }

    public func toArray() -> [Any]! {
        guard isObject, let object = JSValueToObject(context.ref, ref, nil) else { return nil }
        let length = Int(JSValue(ref: object, in: context).forProperty("length")?.toDouble() ?? 0)
        return (0..<length).map { atIndex($0).toObject() ?? NSNull() }
    }

    public func toDictionary() -> [AnyHashable: Any]! {
        guard isObject, let object = JSValueToObject(context.ref, ref, nil) else { return nil }
        let names = JSObjectCopyPropertyNames(context.ref, object)
        defer { JSPropertyNameArrayRelease(names) }
        var result: [AnyHashable: Any] = [:]
        for index in 0..<JSPropertyNameArrayGetCount(names) {
            guard let name = JSPropertyNameArrayGetNameAtIndex(names, index) else { continue }
            let key = JSValue.swiftString(name)
            result[key] = forProperty(key).toObject() ?? NSNull()
        }
        return result
    }

    /// Plain Swift value: Bool, Double, String, [Any], [AnyHashable: Any], or nil.
    public func toObject() -> Any! {
        if isUndefined || isNull { return nil }
        if isBoolean { return toBool() }
        if isNumber { return toDouble() }
        if isString { return toString() as Any }
        if isArray { return toArray() as Any }
        if isObject { return toDictionary() as Any }
        return nil
    }

    /// Strict equality (`===`), as Apple's `isEqual(to:)`.
    public func isEqual(to value: Any!) -> Bool {
        JSValueIsStrictEqual(context.ref, ref, JSValue.make(value, in: context))
    }

    // MARK: Properties and calls

    public func forProperty(_ property: String) -> JSValue! {
        guard isObject, let object = JSValueToObject(context.ref, ref, nil) else { return JSValue(undefinedIn: context) }
        let name = JSStringCreateWithUTF8CString(property)
        defer { JSStringRelease(name) }
        var thrown: JSValueRef?
        let value = JSObjectGetProperty(context.ref, object, name, &thrown)
        if let thrown { context.report(JSValue(ref: thrown, in: context)) }
        return value.map { JSValue(ref: $0, in: context) } ?? JSValue(undefinedIn: context)
    }

    public func setValue(_ value: Any?, forProperty property: String) {
        guard isObject, let object = JSValueToObject(context.ref, ref, nil) else { return }
        let name = JSStringCreateWithUTF8CString(property)
        defer { JSStringRelease(name) }
        var thrown: JSValueRef?
        JSObjectSetProperty(context.ref, object, name, JSValue.make(value, in: context), 0, &thrown)
        if let thrown { context.report(JSValue(ref: thrown, in: context)) }
    }

    public func atIndex(_ index: Int) -> JSValue! {
        guard isObject, let object = JSValueToObject(context.ref, ref, nil) else { return JSValue(undefinedIn: context) }
        var thrown: JSValueRef?
        let value = JSObjectGetPropertyAtIndex(context.ref, object, UInt32(index), &thrown)
        if let thrown { context.report(JSValue(ref: thrown, in: context)) }
        return value.map { JSValue(ref: $0, in: context) } ?? JSValue(undefinedIn: context)
    }

    @discardableResult
    public func call(withArguments arguments: [Any]!) -> JSValue! {
        guard isObject, let function = JSValueToObject(context.ref, ref, nil),
              JSObjectIsFunction(context.ref, function) else { return JSValue(undefinedIn: context) }
        var values: [JSValueRef?] = (arguments ?? []).map { JSValue.make($0, in: context) }
        var thrown: JSValueRef?
        let result = JSObjectCallAsFunction(context.ref, function, nil, values.count, &values, &thrown)
        if let thrown {
            context.report(JSValue(ref: thrown, in: context))
            return JSValue(undefinedIn: context)
        }
        return result.map { JSValue(ref: $0, in: context) } ?? JSValue(undefinedIn: context)
    }

    // MARK: Swift → JS

    static func make(_ value: Any?, in context: JSContext) -> JSValueRef {
        let ctx = context.ref
        guard let value else { return JSValueMakeUndefined(ctx) }
        switch value {
        case let value as JSValue: return value.ref
        case is NSNull: return JSValueMakeNull(ctx)
        case let value as Bool: return JSValueMakeBoolean(ctx, value)
        case let value as String: return makeString(value, ctx)
        case let value as NSString: return makeString(value as String, ctx)
        case let value as Int: return JSValueMakeNumber(ctx, Double(value))
        case let value as Int32: return JSValueMakeNumber(ctx, Double(value))
        case let value as Double: return JSValueMakeNumber(ctx, value)
        case let value as Float: return JSValueMakeNumber(ctx, Double(value))
        case let value as CGFloat: return JSValueMakeNumber(ctx, Double(value))
        case let value as NSNumber: return JSValueMakeNumber(ctx, value.doubleValue)
        case let value as [Any]:
            var items: [JSValueRef?] = value.map { make($0, in: context) }
            return JSObjectMakeArray(ctx, items.count, &items, nil) ?? JSValueMakeUndefined(ctx)
        case let value as [String: Any]:
            let object = JSObjectMake(ctx, nil, nil)
            let wrapper = JSValue(ref: object!, in: context)
            for (key, item) in value { wrapper.setValue(item, forProperty: key) }
            return wrapper.ref
        default:
            if let function = JSFunctionBox.make(value, in: context) { return function }
            return makeString("\(value)", ctx)
        }
    }

    private static func makeString(_ value: String, _ ctx: JSContextRef) -> JSValueRef {
        let string = JSStringCreateWithUTF8CString(value)
        defer { JSStringRelease(string) }
        return JSValueMakeString(ctx, string)
    }

    static func swiftString(_ string: JSStringRef) -> String {
        let capacity = JSStringGetMaximumUTF8CStringSize(string)
        var buffer = [CChar](repeating: 0, count: capacity)
        JSStringGetUTF8CString(string, &buffer, capacity)
        return String(cString: buffer)
    }
}

/// A Swift closure as a JS function: a JS object of a callable class whose private data is the box.
final class JSFunctionBox {
    let call: (JSContext, [JSValue]) -> Any?

    init(_ call: @escaping (JSContext, [JSValue]) -> Any?) { self.call = call }

    /// The closure shapes upstream hands to `setObject(_:forKeyedSubscript:)`.
    static func make(_ value: Any, in context: JSContext) -> JSValueRef? {
        func arg(_ a: [JSValue], _ i: Int) -> JSValue? { i < a.count ? a[i] : nil }
        func string(_ a: [JSValue], _ i: Int) -> String { arg(a, i).flatMap { $0.isUndefined ? nil : $0.toString() } ?? "" }
        func number(_ a: [JSValue], _ i: Int) -> Double { arg(a, i)?.toDouble() ?? 0 }
        let box: JSFunctionBox
        switch value {
        case let f as (String, String) -> Any?:
            box = JSFunctionBox { _, a in f(string(a, 0), string(a, 1)) }
        case let f as (String, String, JSValue?) -> Any?:
            box = JSFunctionBox { _, a in f(string(a, 0), string(a, 1), arg(a, 2)) }
        case let f as (String, String, JSValue?) -> Void:
            box = JSFunctionBox { _, a in f(string(a, 0), string(a, 1), arg(a, 2)); return nil }
        case let f as (String, String) -> Bool:
            box = JSFunctionBox { _, a in f(string(a, 0), string(a, 1)) }
        case let f as (JSValue?, Double, Bool) -> Int:
            box = JSFunctionBox { _, a in f(arg(a, 0), number(a, 1), arg(a, 2)?.toBool() ?? false) }
        case let f as (Int) -> Void:
            box = JSFunctionBox { _, a in f(Int(number(a, 0))); return nil }
        case let f as () -> Void:
            box = JSFunctionBox { _, _ in f(); return nil }
        case let f as (String) -> Void:
            box = JSFunctionBox { _, a in f(string(a, 0)); return nil }
        default:
            return nil
        }
        let object = JSObjectMake(context.ref, functionClass, Unmanaged.passRetained(box).toOpaque())
        return object
    }

    nonisolated(unsafe) static let functionClass: JSClassRef = {
        var definition = kJSClassDefinitionEmpty
        definition.callAsFunction = { ctx, function, _, count, arguments, exception in
            guard let ctx, let function, let context = JSContext.context(for: ctx),
                  let data = JSObjectGetPrivate(function) else { return nil }
            let box = Unmanaged<JSFunctionBox>.fromOpaque(data).takeUnretainedValue()
            let values = (0..<count).compactMap { arguments?[$0].map { JSValue(ref: $0, in: context) } }
            let previous = context.exception
            context.exception = nil
            let result = JSContext.withCurrent(context) { box.call(context, values) }
            // A Swift function "throws" by setting the context's exception, as in Apple's bridge.
            if let thrown = context.exception {
                exception?.pointee = thrown.ref
                context.exception = previous
                return JSValueMakeUndefined(ctx)
            }
            context.exception = previous
            return JSValue.make(result, in: context)
        }
        definition.finalize = { object in
            guard let data = JSObjectGetPrivate(object) else { return }
            Unmanaged<JSFunctionBox>.fromOpaque(data).release()
        }
        return JSClassCreate(&definition)
    }()
}
