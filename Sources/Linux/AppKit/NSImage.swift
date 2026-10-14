import Foundation
import ImageIO
import CoreGraphics
import CGdkPixbuf

/// An image: a CGImage plus a point size. Files decode through gdk-pixbuf (PNG, JPEG, BMP,
/// GIF, WebP, …); `lockFocus` draws into a fresh bitmap.
open class NSImage: @unchecked Sendable {
    public struct Name: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }

    open var size: NSSize
    open var isTemplate = false
    open var accessibilityDescription: String?
    private var image: CGImage?
    private var focusContext: CGContext?
    private var focusPrevious: NSGraphicsContext?

    public init(cgImage: CGImage, size: NSSize) {
        image = cgImage
        self.size = size == .zero ? NSSize(width: cgImage.width, height: cgImage.height) : size
    }

    public init(size: NSSize) { self.size = size }

    public convenience init?(data: Data) {
        guard let decoded = Self.decode(data) else { return nil }
        self.init(cgImage: decoded, size: .zero)
    }

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    public convenience init?(contentsOfFile path: String) { self.init(contentsOf: URL(fileURLWithPath: path)) }

    /// Bundled resource by name, as `NSImage(named:)` finds images in the app bundle.
    public convenience init?(named name: String) {
        let candidates = ["png", "jpg", "bmp", "gif"].compactMap { Bundle.main.url(forResource: name, withExtension: $0) }
        guard let url = candidates.first else { return nil }
        self.init(contentsOf: url)
    }

    public convenience init?(systemSymbolName name: String, accessibilityDescription: String?) { nil }

    public var isValid: Bool { image != nil || focusContext != nil }

    // MARK: Decoding

    private static func decode(_ data: Data) -> CGImage? { decodeImage(data) }

    // MARK: Representations

    open func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?, context: NSGraphicsContext?,
                      hints: [NSImageRep.HintKey: Any]?) -> CGImage? {
        if focusContext != nil { return focusContext?.makeImage() }
        return image
    }

    /// PNG bytes (no TIFF encoder here; callers only round-trip it through NSBitmapImageRep).
    open var tiffRepresentation: Data? { image?.pngData() }

    open var representations: [NSImageRep] { image.map { [NSBitmapImageRep(cgImage: $0)] } ?? [] }

    open func addRepresentation(_ rep: NSImageRep) {
        if let bitmap = rep as? NSBitmapImageRep, let cg = bitmap.cgImage { image = cg }
    }

    // MARK: Drawing into the image

    open func lockFocus() {
        let width = max(1, Int(size.width.rounded(.up))), height = max(1, Int(size.height.rounded(.up)))
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        if let ctx, let image { ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        focusContext = ctx
        focusPrevious = NSGraphicsContext.current
        if let ctx { NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false) }
    }

    open func lockFocusFlipped(_ flipped: Bool) {
        lockFocus()
        if flipped, let ctx = focusContext {
            ctx.translateBy(x: 0, y: CGFloat(ctx.height))
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        }
    }

    open func unlockFocus() {
        image = focusContext?.makeImage() ?? image
        focusContext = nil
        NSGraphicsContext.current = focusPrevious
        focusPrevious = nil
    }

    /// Runs `drawingHandler` into a new image of `size`, as NSImage(size:flipped:drawingHandler:).
    public convenience init(size: NSSize, flipped: Bool, drawingHandler: @escaping (NSRect) -> Bool) {
        self.init(size: size)
        lockFocusFlipped(flipped)
        _ = drawingHandler(NSRect(origin: .zero, size: size))
        unlockFocus()
    }

    // MARK: Drawing the image

    /// Image-space rect (bottom-left origin, points) → CG crop rect (top-left origin, pixels).
    private func pixelRect(for from: NSRect, of cg: CGImage) -> CGRect? {
        guard from != .zero, size.width > 0, size.height > 0 else { return nil }
        let sx = CGFloat(cg.width) / size.width, sy = CGFloat(cg.height) / size.height
        return CGRect(x: from.minX * sx, y: (size.height - from.maxY) * sy, width: from.width * sx, height: from.height * sy)
    }

    open func draw(in rect: NSRect, from fromRect: NSRect, operation op: NSCompositingOperation, fraction delta: CGFloat,
                   respectFlipped: Bool, hints: [NSImageRep.HintKey: Any]?) {
        guard let current = NSGraphicsContext.current, var cg = cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        if let crop = pixelRect(for: fromRect, of: cg), let cropped = cg.cropping(to: crop) { cg = cropped }
        let ctx = current.cgContext
        ctx.saveGState()
        ctx.setBlendMode(op.blendMode)
        ctx.setAlpha(delta)
        if respectFlipped && current.isFlipped {
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(origin: .zero, size: rect.size))
        } else {
            ctx.draw(cg, in: rect)
        }
        ctx.restoreGState()
    }

    open func draw(in rect: NSRect, from fromRect: NSRect, operation op: NSCompositingOperation, fraction delta: CGFloat) {
        draw(in: rect, from: fromRect, operation: op, fraction: delta, respectFlipped: false, hints: nil)
    }

    /// Respects a flipped context, as AppKit's `draw(in:)` does.
    open func draw(in rect: NSRect) {
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    open func draw(at point: NSPoint, from fromRect: NSRect, operation op: NSCompositingOperation, fraction delta: CGFloat) {
        let drawSize = fromRect == .zero ? size : fromRect.size
        draw(in: NSRect(origin: point, size: drawSize), from: fromRect, operation: op, fraction: delta)
    }

    // MARK: Linux helpers

    /// The image scaled to `width`×`height` as tightly packed RGBX bytes, top row first.
    public func rgbxPixels(width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}

open class NSImageRep {
    public struct HintKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let interpolation = HintKey(rawValue: "NSImageHintInterpolation")
        public static let ctm = HintKey(rawValue: "NSImageHintCTM")
    }
    open var size: NSSize = .zero
    public init() {}
    open var pixelsWide: Int { 0 }
    open var pixelsHigh: Int { 0 }
}

open class NSBitmapImageRep: NSImageRep {
    private let storedImage: CGImage?
    /// Drawing target when the rep was created empty (bitmapDataPlanes: nil).
    let bitmapContext: CGContext?

    public init(cgImage: CGImage) {
        storedImage = cgImage
        bitmapContext = nil
        super.init()
        size = NSSize(width: cgImage.width, height: cgImage.height)
    }

    public convenience init?(data: Data) {
        guard let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(cgImage: image)
    }

    /// An empty RGBA bitmap to draw into through `NSGraphicsContext(bitmapImageRep:)`.
    public init?(bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide width: Int,
                 pixelsHigh height: Int, bitsPerSample bps: Int, samplesPerPixel spp: Int, hasAlpha alpha: Bool,
                 isPlanar: Bool, colorSpaceName: NSColorSpaceName, bytesPerRow rBytes: Int, bitsPerPixel pBits: Int) {
        guard planes == nil, bps == 8, !isPlanar,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        storedImage = nil
        bitmapContext = ctx
        super.init()
        size = NSSize(width: width, height: height)
    }

    open var cgImage: CGImage? { bitmapContext?.makeImage() ?? storedImage }

    open override var pixelsWide: Int { bitmapContext?.width ?? storedImage?.width ?? 0 }
    open override var pixelsHigh: Int { bitmapContext?.height ?? storedImage?.height ?? 0 }

    public enum FileType: UInt, Sendable { case tiff, bmp, gif, jpeg, png, jpeg2000 }

    open func representation(using type: FileType, properties: [PropertyKey: Any]) -> Data? {
        cgImage?.pngData()
    }

    public struct PropertyKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let compressionFactor = PropertyKey(rawValue: "NSImageCompressionFactor")
    }
}

public struct NSColorSpaceName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let deviceRGB = NSColorSpaceName(rawValue: "NSDeviceRGBColorSpace")
    public static let calibratedRGB = NSColorSpaceName(rawValue: "NSCalibratedRGBColorSpace")
}
