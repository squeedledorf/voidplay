import Foundation
import CGtk

/// A font request: family, size and weight, realised through Pango when text is drawn.
public final class NSFont: @unchecked Sendable, Hashable {
    public struct Weight: RawRepresentable, Hashable, Sendable, Comparable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(-0.8), thin = Weight(-0.6), light = Weight(-0.4)
        public static let regular = Weight(0), medium = Weight(0.23), semibold = Weight(0.3)
        public static let bold = Weight(0.4), heavy = Weight(0.56), black = Weight(0.62)
        public static func < (a: Weight, b: Weight) -> Bool { a.rawValue < b.rawValue }

        /// Pango's 100–900 scale.
        var pango: Int32 {
            switch rawValue {
            case ..<(-0.7): return 100
            case ..<(-0.5): return 200
            case ..<(-0.2): return 300
            case ..<0.1: return 400
            case ..<0.26: return 500
            case ..<0.35: return 600
            case ..<0.5: return 700
            case ..<0.6: return 800
            default: return 900
            }
        }
    }

    public let familyName: String?
    public let fontName: String
    public let pointSize: CGFloat
    public let weight: Weight
    let monospaced: Bool

    init(family: String, size: CGFloat, weight: Weight = .regular, monospaced: Bool = false) {
        familyName = family
        fontName = family
        pointSize = size
        self.weight = weight
        self.monospaced = monospaced
    }

    public convenience init?(name: String, size: CGFloat) {
        let bold = name.lowercased().contains("bold")
        let family = name.replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Regular", with: "")
        self.init(family: family, size: size, weight: bold ? .bold : .regular)
    }

    public static func systemFont(ofSize size: CGFloat) -> NSFont { NSFont(family: "Sans", size: size) }
    public static func systemFont(ofSize size: CGFloat, weight: Weight) -> NSFont { NSFont(family: "Sans", size: size, weight: weight) }
    public static func boldSystemFont(ofSize size: CGFloat) -> NSFont { NSFont(family: "Sans", size: size, weight: .bold) }
    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> NSFont {
        NSFont(family: "Monospace", size: size, weight: weight, monospaced: true)
    }
    public static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: Weight) -> NSFont {
        NSFont(family: "Sans", size: size, weight: weight)
    }
    public static func userFixedPitchFont(ofSize size: CGFloat) -> NSFont? { monospacedSystemFont(ofSize: size, weight: .regular) }
    public static func labelFont(ofSize size: CGFloat) -> NSFont { systemFont(ofSize: size) }
    public static func menuFont(ofSize size: CGFloat) -> NSFont { systemFont(ofSize: size) }
    public static func titleBarFont(ofSize size: CGFloat) -> NSFont { boldSystemFont(ofSize: size) }
    public static var systemFontSize: CGFloat { 13 }
    public static var smallSystemFontSize: CGFloat { 11 }
    public static var labelFontSize: CGFloat { 10 }

    public func withSize(_ size: CGFloat) -> NSFont { NSFont(family: fontName, size: size, weight: weight, monospaced: monospaced) }

    // Metrics, from Pango at 72 dpi (1 pt = 1 unit, as AppKit).
    public var ascender: CGFloat { metrics.ascent }
    public var descender: CGFloat { -metrics.descent }
    public var capHeight: CGFloat { metrics.ascent * 0.7 }
    public var xHeight: CGFloat { metrics.ascent * 0.5 }
    public var leading: CGFloat { 0 }
    public var boundingRectForFont: NSRect {
        NSRect(x: 0, y: descender, width: pointSize, height: metrics.ascent + metrics.descent)
    }

    private lazy var metrics: (ascent: CGFloat, descent: CGFloat) = TextLayout.metrics(for: self)

    /// Pango font description; the caller frees it.
    func makeDescription() -> OpaquePointer? {
        let description = pango_font_description_new()
        pango_font_description_set_family(description, fontName)
        pango_font_description_set_absolute_size(description, Double(pointSize) * Double(PANGO_SCALE))
        pango_font_description_set_weight(description, PangoWeight(UInt32(weight.pango)))
        return description
    }

    public static func == (a: NSFont, b: NSFont) -> Bool {
        a.fontName == b.fontName && a.pointSize == b.pointSize && a.weight == b.weight
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fontName); hasher.combine(pointSize); hasher.combine(weight)
    }
}

public final class NSFontManager {
    public static let shared = NSFontManager()
    public struct FontTraitMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let boldFontMask = FontTraitMask(rawValue: 2)
        public static let italicFontMask = FontTraitMask(rawValue: 1)
    }
    public func convert(_ font: NSFont, toHaveTrait trait: FontTraitMask) -> NSFont {
        trait.contains(.boldFontMask) ? NSFont(family: font.fontName, size: font.pointSize, weight: .bold) : font
    }
    public var availableFontFamilies: [String] { [] }
}
