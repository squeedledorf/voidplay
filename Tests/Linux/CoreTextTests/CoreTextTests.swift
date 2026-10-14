import XCTest
import Foundation
import CoreGraphics
import CoreText

final class CoreTextTests: XCTestCase {
    func testLineMeasuresAndDraws() throws {
        let font = CTFontCreateWithName("Sans", 16, nil)
        XCTAssertGreaterThan(CTFontGetAscent(font), 8)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello", attributes: [
            NSAttributedString.Key(kCTFontAttributeName): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName): CGColor(red: 1, green: 1, blue: 1, alpha: 1)]))
        XCTAssertGreaterThan(CTLineGetTypographicBounds(line, nil, nil, nil), 20)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 80, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.textPosition = CGPoint(x: 4, y: 8)
        CTLineDraw(line, ctx)
        let data = try XCTUnwrap(ctx.makeImage()?.dataProvider?.data)
        let lit = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 128 }.count
        XCTAssertGreaterThan(lit, 20, "glyph pixels drawn")
    }
}
