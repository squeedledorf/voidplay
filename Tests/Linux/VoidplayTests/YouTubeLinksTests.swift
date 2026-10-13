import XCTest
import Foundation
@testable import voidplay

final class YouTubeLinksTests: XCTestCase {
    func testRecognisesYouTubeHosts() {
        for link in ["https://www.youtube.com/playlist?list=PL1", "https://youtu.be/abc", "https://music.youtube.com/watch?v=x"] {
            XCTAssertTrue(YouTubeLinks.isYouTube(URL(string: link)!), link)
        }
        for link in ["https://notyoutube.com/x", "http://radio.example/stream", "file:///music/youtube.com.mp3"] {
            XCTAssertFalse(YouTubeLinks.isYouTube(URL(string: link)!), link)
        }
    }

    func testEntryBecomesWatchTrackAndHiddenVideosAreDropped() throws {
        let track = try XCTUnwrap(YouTubeLinks.track(["id": "abc123", "title": "Song", "channel": "Band", "duration": 61.0]))
        XCTAssertEqual(track.url.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(track.title, "Song")
        XCTAssertEqual(track.artist, "Band")
        XCTAssertEqual(track.duration, 61)
        XCTAssertNil(YouTubeLinks.track(["id": "x", "title": "[Private video]"]))
        XCTAssertNil(YouTubeLinks.track(["id": "y", "title": "[Deleted video]"]))
    }
}
