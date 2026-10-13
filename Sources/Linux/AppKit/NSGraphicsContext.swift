import Foundation
import CoreGraphics

/// The drawing destination AppKit code reaches through `NSGraphicsContext.current`.
open class NSGraphicsContext {
    public let cgContext: CGContext
    public let isFlipped: Bool
    open var imageInterpolation: NSImageInterpolation = .default {
        didSet {
            switch imageInterpolation {
            case .none: cgContext.interpolationQuality = .none
            case .low: cgContext.interpolationQuality = .low
            case .medium: cgContext.interpolationQuality = .medium
            case .high: cgContext.interpolationQuality = .high
            case .default: cgContext.interpolationQuality = .default
            }
        }
    }
    open var shouldAntialias = true { didSet { cgContext.setShouldAntialias(shouldAntialias) } }
    open var compositingOperation: NSCompositingOperation = .sourceOver

    public init(cgContext: CGContext, flipped: Bool) {
        self.cgContext = cgContext
        self.isFlipped = flipped
    }

    /// Draws into `rep`'s bitmap, in points (scaled to the rep's pixels), unflipped.
    public convenience init?(bitmapImageRep rep: NSBitmapImageRep) {
        guard let ctx = rep.bitmapContext else { return nil }
        if rep.size.width > 0, rep.size.height > 0 {
            ctx.scaleBy(x: CGFloat(rep.pixelsWide) / rep.size.width, y: CGFloat(rep.pixelsHigh) / rep.size.height)
        }
        self.init(cgContext: ctx, flipped: false)
    }

    public static var current: NSGraphicsContext?
    private static var stack: [NSGraphicsContext?] = []

    public static func saveGraphicsState() {
        stack.append(current)
        current?.cgContext.saveGState()
    }

    public static func restoreGraphicsState() {
        current?.cgContext.restoreGState()
        if let previous = stack.popLast() { current = previous }
    }

    open func saveGraphicsState() { cgContext.saveGState() }
    open func restoreGraphicsState() { cgContext.restoreGState() }
    open func flushGraphics() { cgContext.flush() }
}

public enum NSImageInterpolation: UInt, Sendable { case `default`, none, low, medium, high }

public enum NSCompositingOperation: UInt, Sendable {
    case clear, copy, sourceOver, sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn,
         destinationOut, destinationAtop, xor, plusDarker, plusLighter, multiply, screen, overlay,
         darken, lighten, colorDodge, colorBurn, softLight, hardLight, difference, exclusion,
         hue, saturation, color, luminosity

    var blendMode: CGBlendMode {
        switch self {
        case .clear: return .clear
        case .copy: return .copy
        case .sourceOver: return .normal
        case .sourceIn: return .sourceIn
        case .sourceOut: return .sourceOut
        case .sourceAtop: return .sourceAtop
        case .destinationOver: return .destinationOver
        case .destinationIn: return .destinationIn
        case .destinationOut: return .destinationOut
        case .destinationAtop: return .destinationAtop
        case .xor: return .xor
        case .plusDarker: return .plusDarker
        case .plusLighter: return .plusLighter
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        }
    }
}

/// Fills a rect in the current context with the current fill colour (`NSColor.set()`).
public func NSRectFill(_ rect: NSRect) { NSGraphicsContext.current?.cgContext.fill(rect) }
public func __NSRectFill(_ rect: NSRect) { NSRectFill(rect) }

extension NSRect {
    public func fill() { NSRectFill(self) }
    public func fill(using operation: NSCompositingOperation) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(operation.blendMode)
        ctx.fill(self)
        ctx.restoreGState()
    }
    public func frame(withWidth width: CGFloat = 1) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.fill([NSRect(x: minX, y: minY, width: self.width, height: width),
                  NSRect(x: minX, y: maxY - width, width: self.width, height: width),
                  NSRect(x: minX, y: minY, width: width, height: height),
                  NSRect(x: maxX - width, y: minY, width: width, height: height)])
    }
}
