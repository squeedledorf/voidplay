import XCTest
@testable import AppKit

/// Drawing paths the skin code relies on, checked by reading pixels back.
final class ImageDrawingTests: XCTestCase {
    /// 2×2 sprite sheet, top row red | green, bottom row blue | white (memory row 0 = top).
    private func sheet() -> NSImage {
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                               0, 0, 255, 255, 255, 255, 255, 255]
        let cg = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: CGDataProvider(data: Data(pixels))!, decode: nil, shouldInterpolate: false,
                         intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: 2, height: 2))
    }

    private func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let data = image.dataProvider!.data!
        let i = y * image.bytesPerRow + x * 4
        return [data[i + 2], data[i + 1], data[i], data[i + 3]]  // BGRA → RGBA
    }

    func testSpriteFromSheetIntoBitmapRep() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32))
        rep.size = NSSize(width: 4, height: 2)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let image = sheet()
        // Green cell = top-right of the sheet = image-space (x 1, y 1) in AppKit's bottom-left coords.
        image.draw(in: NSRect(x: 3, y: 0, width: 1, height: 2), from: NSRect(x: 1, y: 1, width: 1, height: 1),
                   operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = try XCTUnwrap(rep.cgImage)
        XCTAssertEqual(rgba(out, 3, 0), [0, 255, 0, 255])
        XCTAssertEqual(rgba(out, 0, 0), [0, 0, 0, 0])
    }

    func testCurrentContextIsPerThread() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let done = expectation(description: "background")
        DispatchQueue.global().async {
            XCTAssertNil(NSGraphicsContext.current)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertNotNil(NSGraphicsContext.current)
        NSGraphicsContext.current = nil
    }
}

