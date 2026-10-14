import XCTest
import JavaScriptCore

final class JavaScriptCoreTests: XCTestCase {
    func testEvaluateCallIntoSwiftAndThrow() throws {
        let context = try XCTUnwrap(JSContext(virtualMachine: JSVirtualMachine()))
        XCTAssertEqual(context.evaluateScript("1 + 2")?.toInt32(), 3)

        let get: (String, String) -> Any? = { path, member in "\(path).\(member)" }
        context.setObject(get, forKeyedSubscript: "__get" as NSString)
        XCTAssertEqual(context.evaluateScript("__get('player', 'status')")?.toString(), "player.status")

        let fail: (String) -> Void = { message in
            JSContext.current()?.exception = JSValue(newErrorFromMessage: message, in: JSContext.current()!)
        }
        context.setObject(fail, forKeyedSubscript: "__fail" as NSString)
        var caught: String?
        context.exceptionHandler = { _, exception in caught = exception?.toString() }
        context.evaluateScript("__fail('nope'); 'unreached'")
        XCTAssertEqual(caught, "Error: nope")

        let names = context.evaluateScript("['a', 'b']")?.toArray() as? [String]
        XCTAssertEqual(names, ["a", "b"])
    }
}
