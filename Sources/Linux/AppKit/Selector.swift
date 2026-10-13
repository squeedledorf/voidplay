import Foundation

/// A method name, as `#selector` produces it on Darwin. On Linux the source transformer writes
/// `Selector("Type.method(_:)")` and SelectorRegistry maps the name back to the method.
public struct Selector: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { name = value }
    public var description: String { name }

    /// `Type.method(_:)` / `self.method` / `method(_:)` → `method`.
    var baseName: String {
        let noArgs = name.split(separator: "(", maxSplits: 1).first.map(String.init) ?? name
        return noArgs.split(separator: ".").last.map(String.init) ?? noArgs
    }
}

public func NSSelectorFromString(_ name: String) -> Selector { Selector(name) }
public func NSStringFromSelector(_ selector: Selector) -> String { selector.name }

/// @objc methods by name, registered by code the source transformer generates for upstream files.
public enum SelectorRegistry {
    public typealias Invoker = (_ target: AnyObject, _ sender: Any?) -> Bool
    private static var entries: [String: [(type: String, invoke: Invoker)]] = [:]

    public static func register(_ name: String, type: String, _ invoke: @escaping Invoker) {
        entries[name, default: []].append((type, invoke))
    }

    /// Calls `selector` on `target` with `sender`; false when `target` has no such method.
    @discardableResult
    public static func invoke(_ selector: Selector, on target: AnyObject, sender: Any?) -> Bool {
        for entry in entries[selector.baseName] ?? [] where entry.invoke(target, sender) { return true }
        return false
    }

    public static func responds(_ target: AnyObject, to selector: Selector) -> Bool {
        // Only a call can tell whether the cast succeeds; answer by name for any registered type match.
        !(entries[selector.baseName] ?? []).isEmpty
    }
}

// MARK: - Selector-based Foundation APIs Darwin has and swift-corelibs does not

private final class SelectorObservation {
    weak var observer: AnyObject?
    var token: NSObjectProtocol?
    init(observer: AnyObject) { self.observer = observer }
}

private var selectorObservations: [ObjectIdentifier: [SelectorObservation]] = [:]

extension NotificationCenter {
    public func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {
        let target = observer as AnyObject
        let observation = SelectorObservation(observer: target)
        observation.token = addObserver(forName: name, object: object, queue: nil) { [weak observation] note in
            guard let target = observation?.observer else { return }
            SelectorRegistry.invoke(selector, on: target, sender: note)
        }
        selectorObservations[ObjectIdentifier(target), default: []].append(observation)
    }

    /// Removes selector-based observations as well as block-based ones registered for `observer`.
    public func removeSelectorObservers(_ observer: Any) {
        let key = ObjectIdentifier(observer as AnyObject)
        for observation in selectorObservations.removeValue(forKey: key) ?? [] {
            if let token = observation.token { removeObserver(token) }
        }
    }
}

extension Timer {
    public static func scheduledTimer(timeInterval: TimeInterval, target: Any, selector: Selector,
                                      userInfo: Any?, repeats: Bool) -> Timer {
        let receiver = target as AnyObject
        return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats) { [weak receiver] timer in
            guard let receiver else { timer.invalidate(); return }
            SelectorRegistry.invoke(selector, on: receiver, sender: timer)
        }
    }

    public convenience init(timeInterval: TimeInterval, target: Any, selector: Selector, userInfo: Any?, repeats: Bool) {
        let receiver = target as AnyObject
        self.init(timeInterval: timeInterval, repeats: repeats) { [weak receiver] timer in
            guard let receiver else { timer.invalidate(); return }
            SelectorRegistry.invoke(selector, on: receiver, sender: timer)
        }
    }
}

extension NSObject {
    public func perform(_ selector: Selector, with object: Any?, afterDelay delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            SelectorRegistry.invoke(selector, on: self, sender: object)
        }
    }

    @discardableResult
    public func perform(_ selector: Selector, with object: Any? = nil) -> Any? {
        SelectorRegistry.invoke(selector, on: self, sender: object)
        return nil
    }

    public func responds(to selector: Selector) -> Bool { SelectorRegistry.responds(self, to: selector) }

    public static func cancelPreviousPerformRequests(withTarget target: Any) {}
    public static func cancelPreviousPerformRequests(withTarget target: Any, selector: Selector, object: Any?) {}
}
