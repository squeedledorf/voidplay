import XCTest
import Foundation
@testable import voidplay

final class VisualizationTapTests: XCTestCase {
    /// A 1 kHz sine lights the band around 1 kHz and leaves the low bands dark.
    func testSineLightsItsBand() {
        let tap = VisualizationTap()
        tap.addSpectrumConsumer("test")
        let frames = 2048, rate = 48_000.0
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        defer { left.deallocate(); right.deallocate(); channels.deallocate() }
        channels[0] = left; channels[1] = right
        for i in 0..<frames {
            left[i] = 0.5 * Float(sin(2 * Double.pi * 1000 * Double(i) / rate))
            right[i] = left[i]
        }
        let updated = expectation(forNotification: .audioSpectrumDataUpdated, object: nil)
        tap.process(channels: channels, frames: frames, sampleRate: rate)
        wait(for: [updated], timeout: 2)
        let bands = tap.spectrumData
        // 75 log bands over 20 Hz–20 kHz: 1 kHz sits in band 75·log(50)/log(1000) ≈ 42.
        let peak = bands.indices.max { bands[$0] < bands[$1] }!
        XCTAssertTrue((40...44).contains(peak), "peak band \(peak)")
        XCTAssertGreaterThan(bands[peak], 0.5)
        XCTAssertLessThan(bands[5], 0.1)
    }
}

final class BPMDetectionTests: XCTestCase {
    /// A 120 BPM click track, fed through the tap at about real time, is reported as ~120 BPM.
    func testClickTrackTempo() throws {
        let tap = VisualizationTap()
        tap.addSpectrumConsumer("test")
        let rate = 48_000.0, frames = 2048, beat = Int(rate * 0.5)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        defer { left.deallocate(); right.deallocate(); channels.deallocate() }
        channels[0] = left; channels[1] = right
        var reported: Double?
        let observer = NotificationCenter.default.addObserver(forName: .bpmUpdated, object: nil, queue: nil) { note in
            if let bpm = (note.userInfo?["bpm"] as? NSNumber)?.doubleValue ?? note.userInfo?["bpm"] as? Double { reported = bpm }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var sample = 0
        for _ in 0..<(Int(rate) * 12 / frames) {
            for i in 0..<frames {
                let phase = (sample + i) % beat
                left[i] = phase < 480 ? Float(sin(Double(phase) * 0.6)) * Float(1 - Double(phase) / 480) : 0
                right[i] = left[i]
            }
            sample += frames
            tap.process(channels: channels, frames: frames, sampleRate: rate)
            Thread.sleep(forTimeInterval: 0.018)
            RunLoop.main.run(until: Date())
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let bpm = try XCTUnwrap(reported, "no BPM reported")
        XCTAssertEqual(bpm, 120, accuracy: 3)
    }
}
