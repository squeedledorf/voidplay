import XCTest
import Foundation
@testable import CoreGraphics

/// Pins the Core Graphics behaviours the skin renderers depend on.
final class CGContextTests: XCTestCase {
    private let rgba = CGImageAlphaInfo.premultipliedLast.rawValue

    /// RGBA bytes of pixel (x, y) where y counts rows from the top of memory.
    private func pixel(_ ctx: CGContext, _ x: Int, _ y: Int) -> [UInt8] {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self) + y * ctx.bytesPerRow + x * 4
        return [p[0], p[1], p[2], p[3]]
    }

    private func image(rows: [[UInt8]], width: Int) -> CGImage {
        let bytes = rows.flatMap { $0 }
        return CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: rgba),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testBitmapOriginIsBottomLeft() throws {
        var buffer = [UInt8](repeating: 0, count: 2 * 2 * 4)
        let ctx = try XCTUnwrap(CGContext(data: &buffer, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: rgba))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(pixel(ctx, 0, 1), [255, 0, 0, 255], "y=0 is the bottom row, which is memory row 1")
        XCTAssertEqual(pixel(ctx, 0, 0), [0, 0, 0, 0])
        XCTAssertEqual(Array(buffer[8..<12]), [255, 0, 0, 255], "drawing lands in the caller's buffer")
    }

    func testImagesDrawUprightInYUpAndInvertedWhenFlipped() throws {
        let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
        let img = image(rows: [red, blue], width: 1)  // memory row 0 = top = red
        let upright = try XCTUnwrap(CGContext(data: nil, width: 1, height: 2, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: rgba))
        upright.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 2))
        XCTAssertEqual(pixel(upright, 0, 0), red)
        XCTAssertEqual(pixel(upright, 0, 1), blue)

        let flipped = try XCTUnwrap(CGContext(data: nil, width: 1, height: 2, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: rgba))
        flipped.translateBy(x: 0, y: 2)
        flipped.scaleBy(x: 1, y: -1)
        flipped.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 2))
        XCTAssertEqual(pixel(flipped, 0, 0), blue, "Core Graphics draws images upside down in a flipped space")
    }

    func testCroppingUsesTopLeftPixelCoordinates() throws {
        let a: [UInt8] = [10, 0, 0, 255], b: [UInt8] = [20, 0, 0, 255], c: [UInt8] = [30, 0, 0, 255], d: [UInt8] = [40, 0, 0, 255]
        let img = image(rows: [a + b, c + d], width: 2)
        let crop = try XCTUnwrap(img.cropping(to: CGRect(x: 1, y: 0, width: 1, height: 1)))
        XCTAssertEqual(crop.width, 1)
        let bytes = try XCTUnwrap(crop.dataProvider?.data)
        XCTAssertEqual(bytes[2], 20, "top-right pixel's red, in Cairo's BGRA order")
    }

    func testAlphaAndPremultiplication() throws {
        var buffer = [UInt8](repeating: 0, count: 4)
        let straight = CGImageAlphaInfo.last.rawValue
        let ctx = try XCTUnwrap(CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: rgba))
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.setAlpha(0.5)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(buffer[3], 128, accuracy: 1)
        XCTAssertEqual(buffer[0], 128, accuracy: 1, "premultipliedLast stores premultiplied colour")
        XCTAssertNil(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 16, bytesPerRow: 8,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: straight))
    }

    func testMakeImageSnapshotsAndClearErases() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: rgba))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let snapshot = try XCTUnwrap(ctx.makeImage())
        ctx.clear(CGRect(x: 0, y: 0, width: 4, height: 4))
        XCTAssertEqual(pixel(ctx, 0, 0), [0, 0, 0, 0])
        XCTAssertEqual(snapshot.dataProvider?.data?[1], 255, "the snapshot kept the green")
    }

    func testTransformsAndPaths() {
        let t = CGAffineTransform(translationX: 10, y: 0).scaledBy(x: 2, y: 2)
        XCTAssertEqual(CGPoint(x: 1, y: 1).applying(t), CGPoint(x: 12, y: 2))
        XCTAssertEqual(CGPoint(x: 12, y: 2).applying(t.inverted()), CGPoint(x: 1, y: 1))
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(path.boundingBox.width, 10, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.height, 20, accuracy: 0.001)
    }
}

final class AlphaOnlyContextTests: XCTestCase {
    /// An 8-bit alpha-only context (one byte per pixel) receives coverage, and stays in its buffer.
    func testAlphaOnlyContextHoldsCoverage() throws {
        var bytes = [UInt8](repeating: 0, count: 4 * 2)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 4, height: 2, bitsPerComponent: 8,
                                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceGray(),
                                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        XCTAssertEqual(bytes, [255, 255, 0, 0, 255, 255, 0, 0])
    }
}

final class MaskClipTests: XCTestCase {
    /// A gray mask clips by brightness: white keeps, black removes, for the paints that follow.
    func testGrayMaskClipsLaterFills() throws {
        // 2×1 mask: left white (keep), right black (clip away).
        let pixels: [UInt8] = [255, 0]
        let mask = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                         provider: CGDataProvider(data: Data(pixels))!, decode: nil,
                                         shouldInterpolate: false, intent: .defaultIntent))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: 2, height: 1), mask: mask)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        ctx.restoreGState()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let data = try XCTUnwrap(ctx.makeImage()?.dataProvider?.data)
        XCTAssertEqual(data[3], 255, "left pixel painted")
        XCTAssertEqual(data[7], 0, "right pixel clipped")
    }

    /// Clipping to an "infinitely" tall band still lets paint through (Cairo fixed-point overflow).
    func testHugeClipRectKeepsContent() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.clip(to: CGRect(x: 0, y: -CGFloat.greatestFiniteMagnitude / 2, width: 2, height: .greatestFiniteMagnitude))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let data = try XCTUnwrap(ctx.makeImage()?.dataProvider?.data)
        XCTAssertEqual(data[3], 255, "inside the band")
        XCTAssertEqual(data[3 * 4 + 3], 0, "outside the band")
    }
}

final class FlippedMaskClipTests: XCTestCase {
    /// WMPRenderer's sequence: scene space is y-down (translate+flip), a mask is applied with a
    /// counter-flip around the frame's centre, then the flip is undone and the artwork drawn.
    /// A mask whose top-left pixel keeps must let paint through at the scene's top-left.
    func testCounterFlippedMaskKeepsTopLeft() throws {
        let pixels: [UInt8] = [255, 0, 0, 0]  // 2×2, row 0 (top) = [keep, cut]
        let mask = try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                         provider: CGDataProvider(data: Data(pixels))!, decode: nil,
                                         shouldInterpolate: false, intent: .defaultIntent))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.translateBy(x: 0, y: 2)
        ctx.scaleBy(x: 1, y: -1)                  // scene space: y down
        let frame = CGRect(x: 0, y: 0, width: 2, height: 2), centerY = frame.midY
        ctx.saveGState()
        ctx.translateBy(x: 0, y: centerY); ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -centerY)
        ctx.clip(to: frame, mask: mask)
        ctx.translateBy(x: 0, y: centerY); ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -centerY)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(frame)
        ctx.restoreGState()
        let data = try XCTUnwrap(ctx.makeImage()?.dataProvider?.data)
        let alphas = [data[3], data[7], data[11], data[15]]  // memory order: top-left, top-right, bottom-left, bottom-right
        XCTAssertEqual(alphas, [255, 0, 0, 0])
    }
}

final class TranslatedMaskClipTests: XCTestCase {
    /// Paint under a mask clip lands where the current matrix puts it, not at the origin.
    func testMaskedPaintKeepsTranslation() throws {
        let mask = try XCTUnwrap(CGImage(width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                         provider: CGDataProvider(data: Data([255, 255, 255, 255]))!, decode: nil,
                                         shouldInterpolate: false, intent: .defaultIntent))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.clip(to: CGRect(x: 0, y: 0, width: 4, height: 1), mask: mask)
        ctx.translateBy(x: 2, y: 0)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try XCTUnwrap(ctx.makeImage()?.dataProvider?.data)
        XCTAssertEqual([data[3], data[7], data[11], data[15]], [0, 0, 255, 0])
    }
}
