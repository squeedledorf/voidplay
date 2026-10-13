import XCTest
@testable import voidplay_source_transform

final class SourceTransformTests: XCTestCase {
    func testRewritesSelectorsAndAttributesWithoutMovingLines() {
        let input = """
        final class Controller: NSObject {
            @objc private func toggle(_ sender: NSMenuItem) {}
            @objc func refresh() {}
            @objc dynamic var level = 0
            func build() -> Selector {
                let s = "#selector(notThis)" // #selector(norThis)
                return #selector(Controller.toggle(_:))
            }
        }
        """
        let t = Transformer(input)
        let out = t.run()
        XCTAssertEqual(out.split(separator: "\n", omittingEmptySubsequences: false).count,
                       input.split(separator: "\n", omittingEmptySubsequences: false).count)
        XCTAssertTrue(out.contains("return Selector(\"Controller.toggle(_:)\")"))
        XCTAssertTrue(out.contains("\"#selector(notThis)\" // #selector(norThis)"), "strings and comments untouched")
        XCTAssertFalse(out.contains("@objc"))
        XCTAssertFalse(out.contains("private"), "private dropped so the registry can call it")
        XCTAssertFalse(out.contains("dynamic"))
        XCTAssertEqual(t.methods.map(\.name), ["toggle", "refresh"])
        XCTAssertEqual(t.methods.first?.typePath, "Controller")
        XCTAssertEqual(t.methods.first?.params.first?.type, "NSMenuItem")
    }

    func testNestedTypesAndSkippedScopes() {
        let input = """
        extension Outer {
            final class Inner {
                @objc func a(_ note: Notification) {}
            }
            func helper() { class Local { @objc func ignored() {} } }
        }
        protocol P { @objc func notRegistered() }
        struct G<T> { @objc func genericIgnored() {} }
        """
        let t = Transformer(input)
        _ = t.run()
        XCTAssertEqual(t.methods.map { "\($0.typePath).\($0.name)" }, ["Outer.Inner.a"])
        let code = registrationCode(id: "x", methods: t.methods)
        XCTAssertTrue(code.contains("guard let sender = sender as? Notification"))
        XCTAssertTrue(code.contains("target.a(sender)"))
    }
}
