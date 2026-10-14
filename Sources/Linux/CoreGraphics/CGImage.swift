import Foundation
import CCairo

/// On Linux, `x as CFData` is an identity cast so upstream's `Data(...) as CFData` compiles.
public typealias CFData = Data
// Core Foundation types as the Swift values they bridge to (there is no toll-free bridging here).
public typealias CFString = String
public typealias CFURL = URL
public typealias CFDictionary = [String: Any]

public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let floatComponents = CGBitmapInfo(rawValue: 1 << 8)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrderDefault = CGBitmapInfo([])
    public static let byteOrder16Little = CGBitmapInfo(rawValue: 1 << 12)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder16Big = CGBitmapInfo(rawValue: 3 << 12)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 4 << 12)
}

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}

public enum CGImageByteOrderInfo: UInt32, Sendable {
    case orderMask = 0x7000
    case orderDefault = 0
    case order16Little = 0x1000
    case order32Little = 0x2000
    case order16Big = 0x3000
    case order32Big = 0x4000
}

public final class CGDataProvider: @unchecked Sendable {
    public let data: CFData?
    public init?(data: CFData) { self.data = data }
}

/// Where R, G, B and A sit in a 4-byte pixel, and whether colour is premultiplied.
struct PixelLayout: Equatable {
    var r: Int, g: Int, b: Int, a: Int?   // a == nil: opaque (alpha none/skip)
    var premultiplied: Bool
    var bytesPerPixel = 4
    /// One byte per pixel holding only alpha (`CGImageAlphaInfo.alphaOnly`); colour reads as black.
    var alphaOnly = false

    /// Cairo's ARGB32: premultiplied, native-endian 0xAARRGGBB, i.e. B,G,R,A bytes on little-endian.
    static let cairo = PixelLayout(r: 2, g: 1, b: 0, a: 3, premultiplied: true)

    init(r: Int, g: Int, b: Int, a: Int?, premultiplied: Bool, bytesPerPixel: Int = 4) {
        self.r = r; self.g = g; self.b = b; self.a = a
        self.premultiplied = premultiplied; self.bytesPerPixel = bytesPerPixel
    }

    init?(bitsPerComponent: Int, bitsPerPixel: Int, bitmapInfo: UInt32) {
        guard bitsPerComponent == 8 else { return nil }
        let alpha = CGImageAlphaInfo(rawValue: bitmapInfo & CGBitmapInfo.alphaInfoMask.rawValue) ?? .none
        if bitsPerPixel == 24 {
            self.init(r: 0, g: 1, b: 2, a: nil, premultiplied: true, bytesPerPixel: 3)
            return
        }
        if bitsPerPixel == 8, alpha == .alphaOnly {
            self.init(r: 0, g: 0, b: 0, a: 0, premultiplied: true, bytesPerPixel: 1)
            alphaOnly = true
            return
        }
        if bitsPerPixel == 8, alpha == .none {
            self.init(r: 0, g: 0, b: 0, a: nil, premultiplied: true, bytesPerPixel: 1)
            return
        }
        guard bitsPerPixel == 32 else { return nil }
        let alphaFirst = [.premultipliedFirst, .first, .noneSkipFirst].contains(alpha)
        // Big-endian / default byte order: memory order is the written order.
        var order = alphaFirst ? ["a", "r", "g", "b"] : ["r", "g", "b", "a"]
        if bitmapInfo & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue {
            order.reverse()
        }
        let hasAlpha = [.premultipliedFirst, .premultipliedLast, .first, .last].contains(alpha)
        self.init(r: order.firstIndex(of: "r")!, g: order.firstIndex(of: "g")!, b: order.firstIndex(of: "b")!,
                  a: hasAlpha ? order.firstIndex(of: "a")! : nil,
                  premultiplied: alpha == .premultipliedFirst || alpha == .premultipliedLast)
    }

    /// Copies `width`×`height` pixels between layouts, premultiplying or unpremultiplying as needed.
    static func convert(from src: UnsafeRawPointer, _ srcLayout: PixelLayout, srcStride: Int,
                        to dst: UnsafeMutableRawPointer, _ dstLayout: PixelLayout, dstStride: Int,
                        width: Int, height: Int) {
        let s = src.assumingMemoryBound(to: UInt8.self)
        let d = dst.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let sp = y * srcStride + x * srcLayout.bytesPerPixel
                let dp = y * dstStride + x * dstLayout.bytesPerPixel
                var r = srcLayout.alphaOnly ? 0 : Int(s[sp + srcLayout.r])
                var g = srcLayout.alphaOnly ? 0 : Int(s[sp + srcLayout.g])
                var b = srcLayout.alphaOnly ? 0 : Int(s[sp + srcLayout.b])
                let a = srcLayout.a.map { Int(s[sp + $0]) } ?? 255
                if dstLayout.alphaOnly {
                    d[dp] = UInt8(a)
                    continue
                }
                if srcLayout.a != nil, !srcLayout.premultiplied, dstLayout.premultiplied {
                    r = (r * a + 127) / 255; g = (g * a + 127) / 255; b = (b * a + 127) / 255
                } else if srcLayout.premultiplied, !dstLayout.premultiplied || dstLayout.a == nil, a > 0, a < 255 {
                    r = min(255, (r * 255 + a / 2) / a); g = min(255, (g * 255 + a / 2) / a); b = min(255, (b * 255 + a / 2) / a)
                }
                if dstLayout.bytesPerPixel == 1 {
                    d[dp] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
                    continue
                }
                d[dp + dstLayout.r] = UInt8(r); d[dp + dstLayout.g] = UInt8(g); d[dp + dstLayout.b] = UInt8(b)
                if dstLayout.bytesPerPixel == 4 {
                    // Skip-alpha layouts still have a fourth byte; CG leaves it opaque.
                    let alphaIndex = dstLayout.a ?? (6 - dstLayout.r - dstLayout.g - dstLayout.b)
                    d[dp + alphaIndex] = dstLayout.a == nil ? 255 : UInt8(a)
                }
            }
        }
    }
}

/// An immutable bitmap, held as a Cairo ARGB32 image surface.
public final class CGImage: @unchecked Sendable {
    /// The Cairo surface (`cairo_surface_t *`), for the AppKit and GTK layers.
    public let _surface: OpaquePointer
    public let width: Int
    public let height: Int
    public let bitsPerComponent = 8
    public let bitsPerPixel = 32
    public var bytesPerRow: Int { Int(cairo_image_surface_get_stride(_surface)) }
    public var bitmapInfo: CGBitmapInfo {
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }
    public var alphaInfo: CGImageAlphaInfo { .premultipliedFirst }
    public var colorSpace: CGColorSpace? { .deviceRGB }
    public var shouldInterpolate = true

    /// Takes ownership of a Cairo image surface.
    public init(_surface surface: OpaquePointer) {
        _surface = surface
        width = Int(cairo_image_surface_get_width(surface))
        height = Int(cairo_image_surface_get_height(surface))
    }

    public convenience init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: CGBitmapInfo, provider: CGDataProvider,
                             decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        guard width > 0, height > 0, let data = provider.data, data.count >= bytesPerRow * height,
              let layout = PixelLayout(bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerPixel,
                                       bitmapInfo: bitmapInfo.rawValue),
              let surface = Self.makeSurface(width: width, height: height) else { return nil }
        let stride = Int(cairo_image_surface_get_stride(surface))
        data.withUnsafeBytes { bytes in
            PixelLayout.convert(from: bytes.baseAddress!, layout, srcStride: bytesPerRow,
                                to: cairo_image_surface_get_data(surface), .cairo, dstStride: stride,
                                width: width, height: height)
        }
        cairo_surface_mark_dirty(surface)
        self.init(_surface: surface)
        self.shouldInterpolate = shouldInterpolate
    }

    deinit {
        cairo_surface_destroy(_surface)
    }

    static func makeSurface(width: Int, height: Int) -> OpaquePointer? {
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height))
        guard let surface, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else {
            if let surface { cairo_surface_destroy(surface) }
            return nil
        }
        return surface
    }

    /// Sub-image in pixel coordinates, top-left origin (as CGImageCreateWithImageInRect).
    public func cropping(to rect: CGRect) -> CGImage? {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, r.width >= 1, r.height >= 1,
              let surface = Self.makeSurface(width: Int(r.width), height: Int(r.height)) else { return nil }
        let cr = cairo_create(surface)
        cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
        cairo_set_source_surface(cr, _surface, -Double(r.minX), -Double(r.minY))
        cairo_paint(cr)
        cairo_destroy(cr)
        return CGImage(_surface: surface)
    }

    public func copy() -> CGImage? { cropping(to: CGRect(x: 0, y: 0, width: width, height: height)) }

    /// Pixels in this image's own layout (premultiplied BGRA on little-endian).
    public var dataProvider: CGDataProvider? {
        cairo_surface_flush(_surface)
        guard let base = cairo_image_surface_get_data(_surface) else { return nil }
        return CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height))
    }
}

extension CGImage {
    /// PNG encoding of the image (Cairo's writer).
    public func pngData() -> Data? {
        var data = Data()
        let status = withUnsafeMutablePointer(to: &data) { pointer -> cairo_status_t in
            cairo_surface_write_to_png_stream(_surface, { closure, bytes, length in
                guard let closure, let bytes else { return CAIRO_STATUS_WRITE_ERROR }
                closure.assumingMemoryBound(to: Data.self).pointee.append(bytes, count: Int(length))
                return CAIRO_STATUS_SUCCESS
            }, pointer)
        }
        return status == CAIRO_STATUS_SUCCESS ? data : nil
    }
}
