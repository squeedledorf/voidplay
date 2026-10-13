import Foundation
import CGdkPixbuf

/// Decoded image, backed by a GdkPixbuf (PNG, JPEG, BMP, GIF, WebP, …).
public final class NSImage: @unchecked Sendable {
    private let pixbuf: OpaquePointer

    public init?(data: Data) {
        guard let loader = gdk_pixbuf_loader_new() else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(loader)) }
        let wrote = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return false }
            return gdk_pixbuf_loader_write(loader, base, gsize(bytes.count), nil) != 0
        }
        let closed = gdk_pixbuf_loader_close(loader, nil) != 0
        guard wrote, closed, let decoded = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
        g_object_ref(UnsafeMutableRawPointer(decoded))
        pixbuf = decoded
    }

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    deinit {
        g_object_unref(UnsafeMutableRawPointer(pixbuf))
    }

    public var size: NSSize {
        NSSize(width: CGFloat(gdk_pixbuf_get_width(pixbuf)), height: CGFloat(gdk_pixbuf_get_height(pixbuf)))
    }

    /// The image scaled to `width`×`height` as tightly packed RGBX bytes, top row first.
    public func rgbxPixels(width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0,
              let scaled = gdk_pixbuf_scale_simple(pixbuf, Int32(width), Int32(height), GDK_INTERP_HYPER) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(scaled)) }
        let channels = Int(gdk_pixbuf_get_n_channels(scaled))
        let stride = Int(gdk_pixbuf_get_rowstride(scaled))
        guard channels >= 3, let source = gdk_pixbuf_read_pixels(scaled) else { return nil }
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let s = y * stride + x * channels, d = (y * width + x) * 4
                out[d] = source[s]; out[d + 1] = source[s + 1]; out[d + 2] = source[s + 2]
            }
        }
        return out
    }
}
