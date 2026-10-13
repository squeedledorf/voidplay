import XCTest
import Foundation
@testable import AVFoundation

/// Builds tagged one-second files with the ffmpeg CLI and checks they read back the way
/// upstream's metadata parsers expect from AVFoundation.
final class AVAssetTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("voidplay-avasset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFile(_ name: String, extraArgs: [String] = []) throws -> URL {
        let out = dir.appendingPathComponent(name)
        let cover = dir.appendingPathComponent("cover.png")
        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        if !FileManager.default.fileExists(atPath: cover.path) {
            ffmpeg.arguments = ["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "color=red:s=8x8",
                                "-frames:v", "1", cover.path]
            try ffmpeg.run(); ffmpeg.waitUntilExit()
        }
        let encode = Process()
        encode.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        encode.arguments = ["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1:sample_rate=44100",
                            "-i", cover.path, "-map", "0:a", "-map", "1:v", "-disposition:v", "attached_pic",
                            "-metadata", "title=Song", "-metadata", "artist=Band", "-metadata", "album=Record",
                            "-metadata", "album_artist=Various", "-metadata", "track=3/10", "-metadata", "genre=Rock",
                            "-metadata", "date=1999"] + extraArgs + [out.path]
        try encode.run(); encode.waitUntilExit()
        try XCTSkipIf(encode.terminationStatus != 0, "ffmpeg could not build \(name)")
        return out
    }

    private func check(_ url: URL, format: AVMetadataFormat, genreKey: String, trackKey: String) throws {
        let asset = AVAsset(url: url)
        XCTAssertEqual(CMTimeGetSeconds(asset.duration), 1, accuracy: 0.1)
        XCTAssertEqual(asset.availableMetadataFormats, [format])
        let items = asset.metadata(forFormat: format)
        func common(_ key: AVMetadataKey) -> String? { items.first { $0.commonKey == key }?.stringValue }
        XCTAssertEqual(common(.commonKeyTitle), "Song")
        XCTAssertEqual(common(.commonKeyArtist), "Band")
        XCTAssertEqual(common(.commonKeyAlbumName), "Record")
        XCTAssertEqual(common(.commonKeyCreationDate)?.prefix(4), "1999")
        XCTAssertEqual(items.first { $0.key as? String == genreKey }?.stringValue, "Rock")
        XCTAssertEqual(items.first { $0.key as? String == trackKey }?.numberValue?.intValue, 3)
        XCTAssertNotNil(items.first { $0.commonKey == .commonKeyArtwork }?.dataValue)

        let audio = try XCTUnwrap(asset.tracks(withMediaType: .audio).first)
        let desc = try XCTUnwrap(audio.formatDescriptions.first as? CMFormatDescription)
        XCTAssertEqual(CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee.mSampleRate, 44100)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 1, accuracy: 0.1)
    }

    func testMP3UsesID3Frames() throws {
        try check(makeFile("a.mp3", extraArgs: ["-id3v2_version", "3"]), format: .id3Metadata,
                  genreKey: "TCON", trackKey: "TRCK")
    }

    func testFLACUsesVorbisComments() throws {
        try check(makeFile("a.flac"), format: .vorbisComment, genreKey: "GENRE", trackKey: "TRACKNUMBER")
    }

    func testM4AUsesITunesAtoms() throws {
        try check(makeFile("a.m4a", extraArgs: ["-c:v", "png"]), format: .iTunesMetadata,
                  genreKey: "©gen", trackKey: "trkn")
    }

    func testAsyncLoadAndMissingFile() async throws {
        let asset = AVURLAsset(url: try makeFile("b.flac"))
        let items = try await asset.load(.metadata)
        let art = try XCTUnwrap(items.first { $0.commonKey == .commonKeyArtwork })
        let data = try await art.load(.dataValue)
        XCTAssertNotNil(data)
        XCTAssertThrowsError(try AVAudioFile(forReading: dir.appendingPathComponent("missing.mp3")))
        XCTAssertTrue(AVAsset(url: dir.appendingPathComponent("missing.mp3")).metadata.isEmpty)
    }
}
