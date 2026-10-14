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

final class M3UEntriesTests: XCTestCase {
    func testExtinfTitlesAndLengthsCarryOver() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vp-m3u-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("list.m3u")
        try """
        #EXTM3U
        #EXTINF:251,Band - Song, With Comma
        https://www.youtube.com/watch?v=abc123
        #EXTINF:0,Local
        /music/local.flac
        """.write(to: file, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(Playlist.m3uEntries(from: file))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].url.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(entries[0].title, "Band - Song, With Comma")
        XCTAssertEqual(entries[0].duration, 251)
        XCTAssertTrue(entries[1].url.isFileURL)
        XCTAssertNil(entries[1].duration, "0 means unknown")
    }
}
