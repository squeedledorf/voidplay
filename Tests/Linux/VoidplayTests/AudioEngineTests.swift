import XCTest
import Foundation
@testable import voidplay

/// Drives the libmpv engine with a silent output. Most tests run it untimed, so tracks finish as
/// fast as mpv decodes them and a whole queue plays through in well under a second.
final class AudioEngineTests: XCTestCase {
    private static let dir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voidplay-engine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Play history and scrobble stores write under XDG_DATA_HOME; keep them out of the real one.
        setenv("XDG_DATA_HOME", dir.appendingPathComponent("data").path, 1)
        return dir
    }()

    override class func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeEngine() -> AudioEngine {
        _ = Self.dir
        return AudioEngine(mpvOptions: ["ao": "null", "ao-null-untimed": "yes"])
    }

    private func tone(_ name: String, seconds: Double, title: String) throws -> Track {
        let url = Self.dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            let ffmpeg = Process()
            ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            ffmpeg.arguments = ["ffmpeg", "-loglevel", "error", "-f", "lavfi",
                                "-i", "sine=frequency=440:duration=\(seconds)", "-metadata", "title=\(title)", url.path]
            try ffmpeg.run(); ffmpeg.waitUntilExit()
            try XCTSkipIf(ffmpeg.terminationStatus != 0, "ffmpeg unavailable")
        }
        return Track(url: url)
    }

    /// Plays until the queue is exhausted or `limit` track changes, returning the titles in play order.
    private func playthrough(_ engine: AudioEngine, limit: Int = .max) -> [String] {
        var titles: [String] = []
        let done = expectation(description: "playthrough")
        done.assertForOverFulfill = false
        let center = NotificationCenter.default
        let started = center.addObserver(forName: .audioTrackDidChange, object: engine, queue: nil) { note in
            guard let track = note.userInfo?["track"] as? Track else { return }
            if titles.last != track.title || engine.repeatEnabled { titles.append(track.title) }
            if titles.count >= limit { engine.stop(); done.fulfill() }
        }
        let exhausted = center.addObserver(forName: .audioQueueDidExhaust, object: engine, queue: nil) { _ in
            done.fulfill()
        }
        engine.play()
        wait(for: [done], timeout: 20)
        center.removeObserver(started)
        center.removeObserver(exhausted)
        return titles
    }

    func testQueuePlaysInOrderAndExhausts() throws {
        let engine = makeEngine()
        engine.loadTracks([try tone("a.flac", seconds: 1, title: "A"),
                           try tone("b.flac", seconds: 1, title: "B"),
                           try tone("c.flac", seconds: 1, title: "C")])
        XCTAssertEqual(playthrough(engine), ["A", "B", "C"])
        XCTAssertEqual(engine.state, .stopped)
    }

    func testRepeatOneLoopsTheCurrentTrack() throws {
        let engine = makeEngine()
        engine.loadTracks([try tone("a.flac", seconds: 1, title: "A"), try tone("b.flac", seconds: 1, title: "B")])
        engine.repeatEnabled = true
        XCTAssertEqual(playthrough(engine, limit: 3), ["A", "A", "A"])
    }

    func testShufflePlaysEveryTrackOnce() throws {
        let engine = makeEngine()
        let tracks = try (0..<5).map { try tone("s\($0).flac", seconds: 0.5, title: "S\($0)") }
        engine.shuffleEnabled = true
        engine.loadTracks(tracks)
        let order = playthrough(engine)
        XCTAssertEqual(order.count, 5)
        XCTAssertEqual(Set(order), Set(tracks.map(\.title)))
    }

    /// Real-time playback (silent): each 1 s cue slice should hand over after about a second.
    /// If mpv ignored the end marks, the first track would run the whole 3 s file.
    func testCueTracksPlayTheirSlice() throws {
        let audio = try tone("album.flac", seconds: 3, title: "Album")
        let cue = Self.dir.appendingPathComponent("album.cue")
        try """
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "One"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Two"
            INDEX 01 00:01:00
          TRACK 03 AUDIO
            TITLE "Three"
            INDEX 01 00:02:00
        """.write(to: cue, atomically: true, encoding: .utf8)
        let tracks = try XCTUnwrap(AudioEngine.tracksForCueOrSibling(url: audio.url))
        XCTAssertEqual(tracks.map(\.title), ["One", "Two", "Three"])

        let engine = AudioEngine(mpvOptions: ["ao": "null"])
        engine.loadTracks(tracks)
        var changes: [Date] = []
        let observer = NotificationCenter.default.addObserver(forName: .audioTrackDidChange,
                                                              object: engine, queue: nil) { _ in changes.append(Date()) }
        XCTAssertEqual(playthrough(engine), ["One", "Two", "Three"])
        NotificationCenter.default.removeObserver(observer)
        // Track changes fire when mpv decodes past a boundary, up to an output buffer ahead of the
        // speaker, so a gap can read short; ignored end marks would read as 3 s and 2 s instead.
        let gaps = zip(changes.dropFirst(), changes).map { $0.timeIntervalSince($1) }.filter { $0 > 0.1 }
        XCTAssertEqual(gaps.count, 2)
        for gap in gaps { XCTAssert((0.4...1.4).contains(gap), "slice lasted \(gap) s") }
    }

    func testShuffleOrderNeverRepeatsWithinAPass() {
        var order = ShuffleOrder()
        var current = order.startCycle(count: 6)!
        var seen = [current]
        while let next = order.peekNext(count: 6, current: current, repeating: false) {
            order.commitAdvance(to: next, count: 6, current: current)
            current = next
            seen.append(next)
        }
        XCTAssertEqual(seen.sorted(), Array(0..<6))
        XCTAssertNotNil(order.peekNext(count: 6, current: current, repeating: true), "repeat starts a new pass")
    }
}
