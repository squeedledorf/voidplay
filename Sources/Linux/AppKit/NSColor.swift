import Foundation

/// sRGB colour value. Enough of NSColor for skin colour tables; drawing is the GTK layer's job.
public final class NSColor: NSObject, NSSecureCoding, @unchecked Sendable {
    public let redComponent: CGFloat
    public let greenComponent: CGFloat
    public let blueComponent: CGFloat
    public let alphaComponent: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        redComponent = red; greenComponent = green; blueComponent = blue; alphaComponent = alpha
        super.init()
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(Double(redComponent), forKey: "r"); coder.encode(Double(greenComponent), forKey: "g")
        coder.encode(Double(blueComponent), forKey: "b"); coder.encode(Double(alphaComponent), forKey: "a")
    }

    public required convenience init?(coder: NSCoder) {
        self.init(red: coder.decodeDouble(forKey: "r"), green: coder.decodeDouble(forKey: "g"),
                  blue: coder.decodeDouble(forKey: "b"), alpha: coder.decodeDouble(forKey: "a"))
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSColor else { return false }
        return self == other
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(redComponent); hasher.combine(greenComponent); hasher.combine(blueComponent); hasher.combine(alphaComponent)
        return hasher.finalize()
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

    public func usingColorSpace(_ space: NSColorSpace) -> NSColor? { self }

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

// MARK: - Drawing and conversions

extension NSColor {
    public convenience init(calibratedWhite white: CGFloat, alpha: CGFloat) { self.init(white: white, alpha: alpha) }
    public convenience init(deviceRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }
    public convenience init(deviceWhite white: CGFloat, alpha: CGFloat) { self.init(white: white, alpha: alpha) }
    public convenience init(genericGamma22White white: CGFloat, alpha: CGFloat) { self.init(white: white, alpha: alpha) }

    public convenience init?(cgColor: CGColor) {
        guard let c = cgColor.components, c.count >= 4 else { return nil }
        self.init(red: c[0], green: c[1], blue: c[2], alpha: c[3])
    }

    public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = brightness * saturation, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = brightness - c
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    public var cgColor: CGColor {
        CGColor(red: redComponent, green: greenComponent, blue: blueComponent, alpha: alphaComponent)
    }

    public var whiteComponent: CGFloat { (redComponent + greenComponent + blueComponent) / 3 }
    public var numberOfComponents: Int { 4 }

    public var hueComponent: CGFloat { hsb.h }
    public var saturationComponent: CGFloat { hsb.s }
    public var brightnessComponent: CGFloat { hsb.b }

    private var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        let r = redComponent, g = greenComponent, b = blueComponent
        let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
        var h: CGFloat = 0
        if d > 0 {
            if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : d / maxC, maxC)
    }

    public func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?,
                       blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        red?.pointee = redComponent; green?.pointee = greenComponent
        blue?.pointee = blueComponent; alpha?.pointee = alphaComponent
    }

    public func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?,
                       brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        let v = hsb
        hue?.pointee = v.h; saturation?.pointee = v.s; brightness?.pointee = v.b; alpha?.pointee = alphaComponent
    }

    public func blended(withFraction fraction: CGFloat, of color: NSColor) -> NSColor? {
        let f = max(0, min(1, fraction))
        return NSColor(red: redComponent + (color.redComponent - redComponent) * f,
                       green: greenComponent + (color.greenComponent - greenComponent) * f,
                       blue: blueComponent + (color.blueComponent - blueComponent) * f,
                       alpha: alphaComponent + (color.alphaComponent - alphaComponent) * f)
    }

    public func highlight(withLevel level: CGFloat) -> NSColor? { blended(withFraction: level, of: .white) }
    public func shadow(withLevel level: CGFloat) -> NSColor? { blended(withFraction: level, of: .black) }

    /// Sets fill and stroke colour of the current graphics context.
    public func set() { setFill(); setStroke() }

    public func setFill() {
        NSGraphicsContext.current?.cgContext.setFillColor(red: redComponent, green: greenComponent,
                                                          blue: blueComponent, alpha: alphaComponent)
    }

    public func setStroke() {
        NSGraphicsContext.current?.cgContext.setStrokeColor(red: redComponent, green: greenComponent,
                                                            blue: blueComponent, alpha: alphaComponent)
    }

    // System colours, at macOS dark-appearance values.
    public static let labelColor = NSColor(white: 0.87, alpha: 1)
    public static let secondaryLabelColor = NSColor(white: 0.87, alpha: 0.55)
    public static let tertiaryLabelColor = NSColor(white: 0.87, alpha: 0.25)
    public static let quaternaryLabelColor = NSColor(white: 0.87, alpha: 0.1)
    public static let windowBackgroundColor = NSColor(white: 0.196, alpha: 1)
    public static let controlBackgroundColor = NSColor(white: 0.118, alpha: 1)
    public static let controlColor = NSColor(white: 1, alpha: 0.25)
    public static let disabledControlTextColor = NSColor(white: 1, alpha: 0.35)
    public static let controlTextColor = NSColor(white: 0.87, alpha: 1)
    public static let separatorColor = NSColor(white: 1, alpha: 0.1)
    public static let gridColor = NSColor(white: 0.3, alpha: 1)
    public static let controlAccentColor = NSColor(red: 0, green: 0.48, blue: 1, alpha: 1)
    public static let selectedContentBackgroundColor = NSColor(red: 0, green: 0.35, blue: 0.82, alpha: 1)
    public static let unemphasizedSelectedContentBackgroundColor = NSColor(white: 0.27, alpha: 1)
    public static let textColor = NSColor(white: 1, alpha: 0.85)
    public static let textBackgroundColor = NSColor(white: 0.118, alpha: 1)
    public static let systemRed = NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
    public static let systemGreen = NSColor(red: 0.2, green: 0.84, blue: 0.29, alpha: 1)
    public static let systemBlue = NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 1)
    public static let systemOrange = NSColor(red: 1, green: 0.62, blue: 0.04, alpha: 1)
    public static let systemYellow = NSColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
    public static let systemGray = NSColor(white: 0.56, alpha: 1)
    public static let yellow = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
    public static let orange = NSColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    public static let cyan = NSColor(red: 0, green: 1, blue: 1, alpha: 1)
    public static let magenta = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
    public static let purple = NSColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)
    public static let brown = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)
    public static let darkGray = NSColor(white: 1.0 / 3, alpha: 1)
    public static let lightGray = NSColor(white: 2.0 / 3, alpha: 1)
}
