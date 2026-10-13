import Foundation
import CCairo

/// On Linux, `x as CFArray` is an identity-ish cast so upstream's `[...] as CFArray` compiles.
public typealias CFArray = [Any]

public struct CGGradientDrawingOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 2)
}

/// Colour stops, drawn as a Cairo gradient pattern.
public final class CGGradient: @unchecked Sendable {
    let stops: [(location: Double, color: (r: Double, g: Double, b: Double, a: Double))]

    public init?(colorsSpace space: CGColorSpace?, colors: CFArray, locations: UnsafePointer<CGFloat>?) {
        let colorList = colors.compactMap { $0 as? CGColor }
        guard colorList.count >= 2 else { return nil }
        stops = colorList.enumerated().map { index, color in
            let location = locations.map { Double($0[index]) } ?? Double(index) / Double(colorList.count - 1)
            let c = color.rgba
            return (location, (Double(c.r), Double(c.g), Double(c.b), Double(c.a)))
        }
    }

    public convenience init?(colorsSpace space: CGColorSpace?, colors: CFArray, locations: [CGFloat]?) {
        guard let locations else { self.init(colorsSpace: space, colors: colors, locations: nil as UnsafePointer<CGFloat>?); return }
        let copy = locations
        self.init(colorsSpace: space, colors: colors, locations: copy.withUnsafeBufferPointer { $0.baseAddress! })
    }

    public init?(colorSpace space: CGColorSpace, colorComponents components: UnsafePointer<CGFloat>,
                 locations: UnsafePointer<CGFloat>?, count: Int) {
        guard count >= 2 else { return nil }
        stops = (0..<count).map { i in
            let location = locations.map { Double($0[i]) } ?? Double(i) / Double(count - 1)
            return (location, (Double(components[i * 4]), Double(components[i * 4 + 1]),
                               Double(components[i * 4 + 2]), Double(components[i * 4 + 3])))
        }
    }

    func apply(to pattern: OpaquePointer?) {
        for stop in stops {
            cairo_pattern_add_color_stop_rgba(pattern, stop.location, stop.color.r, stop.color.g, stop.color.b, stop.color.a)
        }
    }
}

extension CGContext {
    public func drawLinearGradient(_ gradient: CGGradient, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {
        let pattern = cairo_pattern_create_linear(start.x, start.y, end.x, end.y)
        gradient.apply(to: pattern)
        if !options.isEmpty { cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD) }
        paintPattern(pattern)
    }

    public func drawRadialGradient(_ gradient: CGGradient, startCenter: CGPoint, startRadius: CGFloat,
                                   endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions) {
        let pattern = cairo_pattern_create_radial(startCenter.x, startCenter.y, startRadius, endCenter.x, endCenter.y, endRadius)
        gradient.apply(to: pattern)
        if !options.isEmpty { cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD) }
        paintPattern(pattern)
    }

    private func paintPattern(_ pattern: OpaquePointer?) {
        cairo_save(_cr)
        cairo_set_source(_cr, pattern)
        cairo_paint(_cr)
        cairo_restore(_cr)
        cairo_pattern_destroy(pattern)
        flush()
    }
}
