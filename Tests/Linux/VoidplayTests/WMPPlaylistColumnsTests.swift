import XCTest
import Foundation
@testable import voidplay

final class WMPPlaylistColumnsTests: XCTestCase {
    func testHeadspaceColumnsReadNameAndTime() throws {
        let columns = try XCTUnwrap(WMPPlaylistColumn.parse("name=Name;Duration=Time"))
        XCTAssertEqual(columns.map(\.label), ["Name", "Time"])
        let item = WMPPlaylistItemSnapshot(title: "Party Like 1999", artist: "Prince", duration: 339.6)
        XCTAssertEqual(columns.map { $0.value(of: item) }, ["Party Like 1999", "5:40"])
        XCTAssertEqual(columns.map(\.isTime), [false, true])
        XCTAssertNil(WMPPlaylistColumn.parse(nil))
        XCTAssertNil(WMPPlaylistColumn.parse(" ; "))
    }

    func testScrollBarThumbSpansTheTrackByTheVisibleShare() {
        let bar = NSRect(x: 0, y: 0, width: 16, height: 132)  // 100 px of track
        let top = WMPClassicListChrome.thumbRect(in: bar, first: 0, visible: 7, total: 14)
        XCTAssertEqual(top, NSRect(x: 0, y: 16, width: 16, height: 50))
        let bottom = WMPClassicListChrome.thumbRect(in: bar, first: 7, visible: 7, total: 14)
        XCTAssertEqual(bottom.maxY, 116)
        XCTAssertEqual(WMPClassicListChrome.hit(NSPoint(x: 8, y: 4), in: bar, first: 0, visible: 7, total: 14), .lineUp)
        XCTAssertEqual(WMPClassicListChrome.hit(NSPoint(x: 8, y: 90), in: bar, first: 0, visible: 7, total: 14), .pageDown)
    }
}
