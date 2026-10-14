import Foundation
import CoreGraphics
import CCairo
import CPangoFc

// Linux stand-in for the slice of CoreText upstream uses (WMP skin text): fonts by name, line
// measurement and drawing, and registering a skin's own TTF/OTF fonts — on Pango and fontconfig.
// One Pango font map serves every thread behind a lock, so fonts a skin registers are seen
// everywhere at once (Pango's default map is per thread).

public typealias CGGlyph = UInt16

let fontLock = NSLock()
nonisolated(unsafe) let fontMap: UnsafeMutablePointer<PangoFontMap> = pango_cairo_font_map_new()
nonisolated(unsafe) let fontContext: OpaquePointer = pango_font_map_create_context(fontMap)

private func locked<T>(_ body: () -> T) -> T {
    fontLock.lock(); defer { fontLock.unlock() }
    return body()
}

// MARK: Fonts

public final class CTFont: @unchecked Sendable {
    let description: OpaquePointer
    public let size: CGFloat

    init(description: OpaquePointer, size: CGFloat) {
        self.description = description
        self.size = size
        pango_font_description_set_absolute_size(description, Double(size) * Double(PANGO_SCALE))
    }

    deinit { pango_font_description_free(description) }

    struct Metrics { let ascent: CGFloat; let descent: CGFloat; let height: CGFloat }

    var metrics: Metrics {
        locked {
            let metrics = pango_context_get_metrics(fontContext, description, nil)
            defer { pango_font_metrics_unref(metrics) }
            let scale = CGFloat(PANGO_SCALE)
            return Metrics(ascent: CGFloat(pango_font_metrics_get_ascent(metrics)) / scale,
                           descent: CGFloat(pango_font_metrics_get_descent(metrics)) / scale,
                           height: CGFloat(pango_font_metrics_get_height(metrics)) / scale)
        }
    }

    /// The family fontconfig actually resolved this request to (e.g. "Liberation Sans" for Arial).
    var resolvedFamily: String {
        locked {
            guard let font = pango_context_load_font(fontContext, description) else { return "" }
            defer { g_object_unref(UnsafeMutableRawPointer(font)) }
            let described = pango_font_describe(font)
            defer { pango_font_description_free(described) }
            return pango_font_description_get_family(described).map { String(cString: $0) } ?? ""
        }
    }
}

/// "Family Bold Italic", as CoreText takes full names; Pango reads the trailing style words.
public func CTFontCreateWithName(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    let description = pango_font_description_from_string(name)!
    return CTFont(description: description, size: size > 0 ? size : 12)
}

public func CTFontCopyFamilyName(_ font: CTFont) -> CFString { font.resolvedFamily }
public func CTFontGetAscent(_ font: CTFont) -> CGFloat { font.metrics.ascent }
public func CTFontGetDescent(_ font: CTFont) -> CGFloat { font.metrics.descent }
public func CTFontGetLeading(_ font: CTFont) -> CGFloat {
    let m = font.metrics
    return max(0, m.height - m.ascent - m.descent)
}
public func CTFontGetSize(_ font: CTFont) -> CGFloat { font.size }

// MARK: Lines

public let kCTFontAttributeName: CFString = "NSFont"
public let kCTForegroundColorAttributeName: CFString = "CTForegroundColor"
public let kCTUnderlineStyleAttributeName: CFString = "NSUnderline"

public struct CTUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let single = CTUnderlineStyle(rawValue: 0x01)
    public static let thick = CTUnderlineStyle(rawValue: 0x02)
    public static let double = CTUnderlineStyle(rawValue: 0x09)
}

/// One line of text in one font and colour (the attributes at its first character).
public final class CTLine: @unchecked Sendable {
    let text: String
    let font: CTFont?
    let color: CGColor?
    let underline: Bool

    init(text: String, font: CTFont?, color: CGColor?, underline: Bool) {
        self.text = text
        self.font = font
        self.color = color
        self.underline = underline
    }

    /// A layout for this line on the shared context (call with the lock held).
    func makeLayout() -> OpaquePointer {
        let layout = pango_layout_new(fontContext)!
        pango_layout_set_text(layout, text, -1)
        if let font { pango_layout_set_font_description(layout, font.description) }
        if underline {
            let attributes = pango_attr_list_new()
            pango_attr_list_insert(attributes, pango_attr_underline_new(PANGO_UNDERLINE_SINGLE))
            pango_layout_set_attributes(layout, attributes)
            pango_attr_list_unref(attributes)
        }
        return layout
    }
}

public func CTLineCreateWithAttributedString(_ string: NSAttributedString) -> CTLine {
    let attributes = string.length > 0 ? string.attributes(at: 0, effectiveRange: nil) : [:]
    let underline = (attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName)] as? Int32).map { $0 != 0 }
        ?? (attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName)] as? Int).map { $0 != 0 } ?? false
    return CTLine(text: string.string,
                  font: attributes[NSAttributedString.Key(kCTFontAttributeName)] as? CTFont,
                  color: attributes[NSAttributedString.Key(kCTForegroundColorAttributeName)] as? CGColor,
                  underline: underline)
}

/// Advance width; ascent/descent/leading of the line's font when asked.
public func CTLineGetTypographicBounds(_ line: CTLine, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                       _ descent: UnsafeMutablePointer<CGFloat>?,
                                       _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    if let font = line.font {
        let m = font.metrics
        ascent?.pointee = m.ascent
        descent?.pointee = m.descent
        leading?.pointee = max(0, m.height - m.ascent - m.descent)
    }
    return locked {
        let layout = line.makeLayout()
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        var ink = PangoRectangle(), logical = PangoRectangle()
        pango_layout_get_extents(layout, &ink, &logical)
        return Double(logical.width) / Double(PANGO_SCALE)
    }
}

/// Draws the line with its baseline at the context's `textPosition`, glyphs upright in a y-up
/// user space (Core Graphics text space), as CoreText does.
public func CTLineDraw(_ line: CTLine, _ context: CGContext) {
    let cr = context._cr
    context._willDrawExternally()
    locked {
        cairo_save(cr)
        cairo_translate(cr, Double(context.textPosition.x), Double(context.textPosition.y))
        cairo_scale(cr, 1, -1)
        let c = (line.color ?? CGColor(gray: 0, alpha: 1)).rgba
        cairo_set_source_rgba(cr, Double(c.r), Double(c.g), Double(c.b), Double(c.a))
        pango_cairo_update_context(cr, fontContext)
        let options = cairo_font_options_create()
        cairo_font_options_set_antialias(options, context._textAntialiased ? CAIRO_ANTIALIAS_GRAY : CAIRO_ANTIALIAS_NONE)
        pango_cairo_context_set_font_options(fontContext, options)
        cairo_font_options_destroy(options)
        let layout = line.makeLayout()
        if let first = pango_layout_get_line_readonly(layout, 0) {
            cairo_move_to(cr, 0, 0)
            context._masked { pango_cairo_show_layout_line(cr, first) }
        }
        g_object_unref(UnsafeMutableRawPointer(layout))
        cairo_restore(cr)
    }
    context._didDrawExternally()
}

// MARK: Fonts shipped in a skin

/// A font file's contents, kept on disk so fontconfig can read it.
public final class CGFont: @unchecked Sendable {
    let path: String
    public let postScriptName: CFString?
    let family: String?

    public init?(_ provider: CGDataProvider) {
        guard let data = provider.data else { return nil }
        let name = "voidplay-font-\(getpid())-\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return nil }
        path = url.path
        var count: Int32 = 0
        guard let pattern = FcFreeTypeQuery(path, 0, nil, &count) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        defer { FcPatternDestroy(pattern) }
        func string(_ key: String) -> String? {
            var value: UnsafeMutablePointer<FcChar8>?
            guard FcPatternGetString(pattern, key, 0, &value) == FcResultMatch, let value else { return nil }
            return String(cString: value)
        }
        postScriptName = string(FC_POSTSCRIPT_NAME)
        family = string(FC_FAMILY)
    }
}

/// Makes the font available to every later lookup in this process.
public func CTFontManagerRegisterGraphicsFont(_ font: CGFont, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
    locked {
        guard FcConfigAppFontAddFile(nil, font.path) != 0 else { return false }
        pango_fc_font_map_config_changed(cpangofc_fc_font_map(fontMap))
        return true
    }
}

public typealias CFError = NSError

public func CTFontCreateWithGraphicsFont(_ font: CGFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?,
                                         _ attributes: Any?) -> CTFont {
    let description = pango_font_description_new()!
    pango_font_description_set_family(description, font.family ?? "Sans")
    return CTFont(description: description, size: size > 0 ? size : 12)
}

public func CTFontManagerCopyAvailableFontFamilyNames() -> CFArray {
    locked {
        var families: UnsafeMutablePointer<UnsafeMutablePointer<PangoFontFamily>?>?
        var count: Int32 = 0
        pango_font_map_list_families(fontMap, &families, &count)
        defer { g_free(families) }
        return (0..<Int(count)).compactMap { index in
            families?[index].flatMap { pango_font_family_get_name($0) }.map { String(cString: $0) }
        }
    }
}
