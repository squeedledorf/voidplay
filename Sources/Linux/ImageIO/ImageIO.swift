import Foundation
import CoreGraphics
import CGdkPixbuf

// Linux stand-in for the slice of ImageIO upstream uses: decoding (gdk-pixbuf, so BMP, PNG, GIF,
// JPEG and the rest it has loaders for), image properties, and writing PNG.
//
// ponytail: an animated GIF decodes to its first frame only (count 1, no frame delays). Add
// frames through GdkPixbufAnimationIter when a skin needs them to move.

public let kCGImageSourceShouldCache: CFString = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately: CFString = "kCGImageSourceShouldCacheImmediately"
public let kCGImagePropertyPixelWidth: CFString = "PixelWidth"
public let kCGImagePropertyPixelHeight: CFString = "PixelHeight"
public let kCGImagePropertyGIFDictionary: CFString = "{GIF}"
public let kCGImagePropertyGIFDelayTime: CFString = "DelayTime"
public let kCGImagePropertyGIFUnclampedDelayTime: CFString = "UnclampedDelayTime"
public let kCGImagePropertyGIFLoopCount: CFString = "LoopCount"

public final class CGImageSource: @unchecked Sendable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}

public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? {
    decodeImage(data as Data).map(CGImageSource.init)
}

public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
    (try? Data(contentsOf: url)).flatMap { CGImageSourceCreateWithData($0 as NSData, options) }
}

public func CGImageSourceGetCount(_ source: CGImageSource) -> Int { 1 }

public func CGImageSourceCreateImageAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    index == 0 ? source.image : nil
}

public func CGImageSourceCopyPropertiesAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CFDictionary? {
    [kCGImagePropertyPixelWidth: source.image.width, kCGImagePropertyPixelHeight: source.image.height]
}

public func CGImageSourceCopyProperties(_ source: CGImageSource, _ options: CFDictionary?) -> CFDictionary? { [:] }

/// gdk-pixbuf decode to a CGImage (RGB or straight RGBA rows as the loader produced them).
public func decodeImage(_ data: Data) -> CGImage? {
    guard let loader = gdk_pixbuf_loader_new() else { return nil }
    defer { g_object_unref(UnsafeMutableRawPointer(loader)) }
    let wrote = data.withUnsafeBytes { bytes -> Bool in
        guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return false }
        return gdk_pixbuf_loader_write(loader, base, gsize(bytes.count), nil) != 0
    }
    let closed = gdk_pixbuf_loader_close(loader, nil) != 0
    guard wrote, closed, let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
    let width = Int(gdk_pixbuf_get_width(pixbuf)), height = Int(gdk_pixbuf_get_height(pixbuf))
    let channels = Int(gdk_pixbuf_get_n_channels(pixbuf)), stride = Int(gdk_pixbuf_get_rowstride(pixbuf))
    guard channels == 3 || channels == 4, let pixels = gdk_pixbuf_read_pixels(pixbuf) else { return nil }
    // gdk-pixbuf rows are padded to `stride`; the last row may be short, so copy row by row.
    var packed = Data(count: stride * height)
    packed.withUnsafeMutableBytes { dst in
        for y in 0..<height {
            memcpy(dst.baseAddress! + y * stride, pixels + y * stride, width * channels)
        }
    }
    let alpha = channels == 4 ? CGImageAlphaInfo.last : CGImageAlphaInfo.none
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: channels * 8, bytesPerRow: stride,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
                   provider: CGDataProvider(data: packed)!, decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent)
}

// MARK: Writing (PNG only)

public final class CGImageDestination: @unchecked Sendable {
    let url: URL
    var images: [CGImage] = []
    init(url: URL) { self.url = url }
}

public func CGImageDestinationCreateWithURL(_ url: CFURL, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    type.lowercased().contains("png") ? CGImageDestination(url: url) : nil
}

public func CGImageDestinationAddImage(_ destination: CGImageDestination, _ image: CGImage, _ properties: CFDictionary?) {
    destination.images.append(image)
}

public func CGImageDestinationFinalize(_ destination: CGImageDestination) -> Bool {
    guard let data = destination.images.first?.pngData() else { return false }
    return (try? data.write(to: destination.url)) != nil
}
