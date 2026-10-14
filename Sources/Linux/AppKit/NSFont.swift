import Foundation
import CoreText

/// AppKit's font is CoreText's (toll-free bridged on macOS): one Pango-backed request type.
public typealias NSFont = CTFont

extension CTFont {
    /// A face by family or PostScript-style name ("Tahoma", "Arial-BoldItalic"); nil when this
    /// system has nothing for it, as AppKit answers.
    public convenience init?(name: String, size: CGFloat) {
        var family = name
        var style = ""
        if let dash = name.lastIndex(of: "-") {
            let suffix = name[name.index(after: dash)...].lowercased()
            if ["bold", "italic", "bolditalic", "oblique", "boldoblique", "regular", "roman"].contains(suffix) {
                family = String(name[..<dash])
                style = suffix
            }
        }
        guard CTFont.familyIsAvailable(family) else { return nil }
        self.init(family: family, size: size, weight: style.hasPrefix("bold") ? .bold : .regular,
                  italic: style.contains("italic") || style.contains("oblique"))
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

    // Metrics, from Pango (1 pt = 1 unit, as AppKit).
    public var ascender: CGFloat { metrics.ascent }
    public var descender: CGFloat { -metrics.descent }
    public var capHeight: CGFloat { metrics.ascent * 0.7 }
    public var xHeight: CGFloat { metrics.ascent * 0.5 }
    public var leading: CGFloat { 0 }
    public var boundingRectForFont: NSRect {
        NSRect(x: 0, y: descender, width: pointSize, height: metrics.ascent + metrics.descent)
    }
}

public typealias NSFontTraitMask = NSFontManager.FontTraitMask

public final class NSFontManager {
    public static let shared = NSFontManager()
    public struct FontTraitMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let italicFontMask = FontTraitMask(rawValue: 1)
        public static let boldFontMask = FontTraitMask(rawValue: 2)
        public static let unboldFontMask = FontTraitMask(rawValue: 4)
        public static let unitalicFontMask = FontTraitMask(rawValue: 0x0100_0000)
    }

    public func convert(_ font: NSFont, toHaveTrait trait: FontTraitMask) -> NSFont {
        var weight: NSFont.Weight?
        var italic: Bool?
        if trait.contains(.boldFontMask) { weight = .bold }
        if trait.contains(.unboldFontMask) { weight = .regular }
        if trait.contains(.italicFontMask) { italic = true }
        if trait.contains(.unitalicFontMask) { italic = false }
        return font.with(weight: weight, italic: italic)
    }

    /// `weight` on AppKit's 0–15 scale (5 regular, 9 bold); nil when the family is not on this system.
    public func font(withFamily family: String, traits: FontTraitMask, weight: Int, size: CGFloat) -> NSFont? {
        guard CTFont.familyIsAvailable(family) else { return nil }
        let bold = traits.contains(.boldFontMask) || weight >= 8
        return NSFont(family: family, size: size, weight: bold ? .bold : .regular, italic: traits.contains(.italicFontMask))
    }

    public var availableFontFamilies: [String] { CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [] }
}
