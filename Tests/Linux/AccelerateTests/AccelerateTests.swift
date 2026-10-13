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
