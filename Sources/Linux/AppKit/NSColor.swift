import Foundation

/// sRGB colour value. Enough of NSColor for skin colour tables; drawing is the GTK layer's job.
public final class NSColor: @unchecked Sendable, Equatable {
    public enum ColorSpace { case sRGB, deviceRGB, genericRGB }

    public let redComponent: CGFloat
    public let greenComponent: CGFloat
    public let blueComponent: CGFloat
    public let alphaComponent: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        redComponent = red; greenComponent = green; blueComponent = blue; alphaComponent = alpha
    }

    public convenience init(calibratedRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    public convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    public convenience init(white: CGFloat, alpha: CGFloat) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    public func usingColorSpace(_ space: ColorSpace) -> NSColor? { self }

    public func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        NSColor(red: redComponent, green: greenComponent, blue: blueComponent, alpha: alpha)
    }

    public static func == (a: NSColor, b: NSColor) -> Bool {
        a.redComponent == b.redComponent && a.greenComponent == b.greenComponent
            && a.blueComponent == b.blueComponent && a.alphaComponent == b.alphaComponent
    }

    public static let black = NSColor(white: 0, alpha: 1)
    public static let white = NSColor(white: 1, alpha: 1)
    public static let clear = NSColor(white: 0, alpha: 0)
    public static let red = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
    public static let green = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    public static let blue = NSColor(red: 0, green: 0, blue: 1, alpha: 1)
    public static let gray = NSColor(white: 0.5, alpha: 1)
}

/// Font request (family + size). Resolved to a real font by the GTK layer.
public final class NSFont: @unchecked Sendable {
    public let fontName: String
    public let pointSize: CGFloat

    public init?(name: String, size: CGFloat) { fontName = name; pointSize = size }
    private init(system size: CGFloat, mono: Bool) { fontName = mono ? "monospace" : "sans-serif"; pointSize = size }

    public static func systemFont(ofSize size: CGFloat) -> NSFont { NSFont(system: size, mono: false) }
    public static func boldSystemFont(ofSize size: CGFloat) -> NSFont { NSFont(system: size, mono: false) }
    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Any? = nil) -> NSFont {
        NSFont(system: size, mono: true)
    }
}
