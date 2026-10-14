import XCTest
import Foundation
@testable import Accelerate

final class AccelerateTests: XCTestCase {
    func testFFTMatchesNaiveDFT() throws {
        let n = 64
        let re = (0..<n).map { Float(sin(Double($0) * 0.7) + 0.3 * cos(Double($0) * 2.1)) }
        let im = (0..<n).map { Float(0.1 * Double($0 % 5)) }
        var outRe = [Float](repeating: 0, count: n), outIm = outRe
        let setup = try XCTUnwrap(vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD))
        vDSP_DFT_Execute(setup, re, im, &outRe, &outIm)
        for k in 0..<n {
            var sr = 0.0, si = 0.0
            for t in 0..<n {
                let a = -2 * Double.pi * Double(k * t) / Double(n)
                sr += Double(re[t]) * cos(a) - Double(im[t]) * sin(a)
                si += Double(re[t]) * sin(a) + Double(im[t]) * cos(a)
            }
            XCTAssertEqual(Double(outRe[k]), sr, accuracy: 1e-3)
            XCTAssertEqual(Double(outIm[k]), si, accuracy: 1e-3)
        }
        XCTAssertNil(vDSP_DFT_zop_CreateSetup(nil, 48, .FORWARD))
    }

    func testVectorReductions() {
        let v: [Float] = [1, -4, 2, 3]
        var r: Float = 0
        vDSP_maxmgv(v, 1, &r, 4); XCTAssertEqual(r, 4)
        vDSP_svesq(v, 1, &r, 4); XCTAssertEqual(r, 30)
        vDSP_meanv(v, 1, &r, 4); XCTAssertEqual(r, 0.5)
        vDSP_meanv(v, 2, &r, 2); XCTAssertEqual(r, 1.5)
    }
}

final class ClassicFFTTests: XCTestCase {
    /// A full-scale cosine at bin 4 of a 16-point frame reads 16·2/2 = 16 there (zrip's ×2 on N/2).
    func testZripPutsCosineInItsBin() {
        let log2n: vDSP_Length = 4, n = 16, half = 8
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        let signal = (0..<n).map { Float(cos(2 * Double.pi * 4 * Double($0) / Double(n))) }
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { r in imag.withUnsafeMutableBufferPointer { i in
            var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
            signal.withUnsafeBufferPointer { s in
                s.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
            }
            vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
        } }
        XCTAssertEqual(magnitudes[4], 16, accuracy: 0.01)
        XCTAssertEqual(magnitudes[3], 0, accuracy: 0.01)
    }
}
