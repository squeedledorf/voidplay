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


final class FlippedViewDrawingTests: XCTestCase {
    private final class FlippedImageView: NSView {
        var image: NSImage?
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// A flipped view drawing with respectFlipped keeps the image upright: its top row on top.
    func testFlippedViewDrawsImageUpright() throws { try MainActor.assumeIsolated {
        // 1×2 image: top row red, bottom row blue (memory row 0 = top).
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]
        let cg = try XCTUnwrap(CGImage(width: 1, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                       provider: CGDataProvider(data: Data(pixels))!, decode: nil,
                                       shouldInterpolate: false, intent: .defaultIntent))
        let view = FlippedImageView(frame: NSRect(x: 0, y: 0, width: 1, height: 2))
        view.image = NSImage(cgImage: cg, size: NSSize(width: 1, height: 2))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 1, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        view.drawTree(in: ctx, dirty: view.bounds)
        let out = try XCTUnwrap(ctx.makeImage()).dataProvider!.data!
        XCTAssertEqual([out[2], out[1], out[0]], [255, 0, 0], "top row should be red")
        XCTAssertEqual([out[6], out[5], out[4]], [0, 0, 255], "bottom row should be blue")
    } }
}

final class NestedFlipTests: XCTestCase {
    private final class Flipped: NSView { override var isFlipped: Bool { true } }

    /// A normal view inside a flipped one keeps its own y-up space: (0, 0) is its bottom-left,
    /// which sits at the bottom of its frame in the flipped parent.
    func testNormalChildOfFlippedParentConvertsUpright() { MainActor.assumeIsolated {
        let parent = Flipped(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let child = NSView(frame: NSRect(x: 0, y: 2, width: 10, height: 4))  // parent rows 2..6, from the top
        parent.addSubview(child)
        // Child's bottom-left is parent y 6 (flipped), i.e. window y 4 (y-up, height 10).
        XCTAssertEqual(child.convert(NSPoint(x: 0, y: 0), to: nil).y, 4, accuracy: 0.001)
        XCTAssertEqual(child.convert(NSPoint(x: 0, y: 4), to: nil).y, 8, accuracy: 0.001)
    } }
}
