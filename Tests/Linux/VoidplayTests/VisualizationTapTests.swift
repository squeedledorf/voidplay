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
