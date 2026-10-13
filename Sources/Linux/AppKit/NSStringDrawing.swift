import Foundation
import CoreGraphics
import CGtk

// Text attributes and drawing, as AppKit's NSStringDrawing, laid out by Pango at 72 dpi so a
// point is one user-space unit.

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let underlineStyle = NSAttributedString.Key("NSUnderline")
    public static let strikethroughStyle = NSAttributedString.Key("NSStrikethrough")
    public static let strokeColor = NSAttributedString.Key("NSStrokeColor")
    public static let strokeWidth = NSAttributedString.Key("NSStrokeWidth")
    public static let shadow = NSAttributedString.Key("NSShadow")
    public static let baselineOffset = NSAttributedString.Key("NSBaselineOffset")
    public static let obliqueness = NSAttributedString.Key("NSObliqueness")
    public static let expansion = NSAttributedString.Key("NSExpansion")
    public static let ligature = NSAttributedString.Key("NSLigature")
    public static let link = NSAttributedString.Key("NSLink")
    public static let toolTip = NSAttributedString.Key("NSToolTip")
    public static let cursor = NSAttributedString.Key("NSCursor")
}

public enum NSTextAlignment: Int, Sendable { case left = 0, right, center, justified, natural }
public enum NSLineBreakMode: UInt, Sendable {
    case byWordWrapping = 0, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

open class NSParagraphStyle: NSObject, @unchecked Sendable {
    public internal(set) var alignment: NSTextAlignment = .natural
    public internal(set) var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public internal(set) var lineSpacing: CGFloat = 0
    public internal(set) var paragraphSpacing: CGFloat = 0
    public internal(set) var firstLineHeadIndent: CGFloat = 0
    public internal(set) var headIndent: CGFloat = 0
    public internal(set) var tailIndent: CGFloat = 0
    public internal(set) var minimumLineHeight: CGFloat = 0
    public internal(set) var maximumLineHeight: CGFloat = 0
    public internal(set) var lineHeightMultiple: CGFloat = 0
    public static let `default` = NSParagraphStyle()
    public override init() {}
}

open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {
    open override var alignment: NSTextAlignment { get { super.alignment } set { super.alignment = newValue } }
    open override var lineBreakMode: NSLineBreakMode { get { super.lineBreakMode } set { super.lineBreakMode = newValue } }
    open override var lineSpacing: CGFloat { get { super.lineSpacing } set { super.lineSpacing = newValue } }
    open override var paragraphSpacing: CGFloat { get { super.paragraphSpacing } set { super.paragraphSpacing = newValue } }
    open override var firstLineHeadIndent: CGFloat { get { super.firstLineHeadIndent } set { super.firstLineHeadIndent = newValue } }
    open override var headIndent: CGFloat { get { super.headIndent } set { super.headIndent = newValue } }
    open override var tailIndent: CGFloat { get { super.tailIndent } set { super.tailIndent = newValue } }
    open override var minimumLineHeight: CGFloat { get { super.minimumLineHeight } set { super.minimumLineHeight = newValue } }
    open override var maximumLineHeight: CGFloat { get { super.maximumLineHeight } set { super.maximumLineHeight = newValue } }
    open override var lineHeightMultiple: CGFloat { get { super.lineHeightMultiple } set { super.lineHeightMultiple = newValue } }
}

open class NSShadow: NSObject, @unchecked Sendable {
    open var shadowColor: NSColor?
    open var shadowOffset = NSSize.zero
    open var shadowBlurRadius: CGFloat = 0
    public override init() {}
}

public struct NSUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = NSUnderlineStyle(rawValue: 1)
    public static let thick = NSUnderlineStyle(rawValue: 2)
    public static let double = NSUnderlineStyle(rawValue: 9)
}

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 2)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 32)
}

public final class NSStringDrawingContext {
    public init() {}
}

enum TextLayout {
    /// A layout measuring off-screen, sharing one Pango context.
    private static let measuringContext: OpaquePointer? = {
        let context = pango_font_map_create_context(pango_cairo_font_map_get_default())
        pango_cairo_context_set_resolution(context, 72)
        return context
    }()

    /// Builds a layout for `text`; `cr` nil means a measuring layout. The caller unrefs it.
    static func make(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat?, cr: OpaquePointer?) -> OpaquePointer? {
        let layout: OpaquePointer?
        if let cr {
            layout = pango_cairo_create_layout(cr)
            pango_cairo_context_set_resolution(pango_layout_get_context(layout), 72)
            pango_layout_context_changed(layout)
        } else {
            layout = pango_layout_new(measuringContext)
        }
        let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 12)
        let description = font.makeDescription()
        pango_layout_set_font_description(layout, description)
        pango_font_description_free(description)
        pango_layout_set_text(layout, text, -1)

        let list = pango_attr_list_new()
        if let kern = attributes[.kern] as? CGFloat ?? (attributes[.kern] as? NSNumber).map({ CGFloat($0.doubleValue) }), kern != 0 {
            pango_attr_list_insert(list, pango_attr_letter_spacing_new(Int32(kern * CGFloat(PANGO_SCALE))))
        }
        if let underline = attributes[.underlineStyle] as? Int ?? (attributes[.underlineStyle] as? NSNumber)?.intValue, underline != 0 {
            pango_attr_list_insert(list, pango_attr_underline_new(PANGO_UNDERLINE_SINGLE))
        }
        pango_layout_set_attributes(layout, list)
        pango_attr_list_unref(list)

        let style = attributes[.paragraphStyle] as? NSParagraphStyle
        switch style?.alignment ?? .natural {
        case .center: pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER)
        case .right: pango_layout_set_alignment(layout, PANGO_ALIGN_RIGHT)
        case .justified: pango_layout_set_justify(layout, 1)
        default: pango_layout_set_alignment(layout, PANGO_ALIGN_LEFT)
        }
        if let width, width > 0 {
            pango_layout_set_width(layout, Int32(width * CGFloat(PANGO_SCALE)))
            switch style?.lineBreakMode ?? .byWordWrapping {
            case .byWordWrapping: pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
            case .byCharWrapping: pango_layout_set_wrap(layout, PANGO_WRAP_CHAR)
            case .byClipping: pango_layout_set_width(layout, -1)
            case .byTruncatingHead: pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_START)
            case .byTruncatingTail: pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END)
            case .byTruncatingMiddle: pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_MIDDLE)
            }
        }
        if let spacing = style?.lineSpacing, spacing > 0 {
            pango_layout_set_spacing(layout, Int32(spacing * CGFloat(PANGO_SCALE)))
        }
        return layout
    }

    static func size(of layout: OpaquePointer?) -> NSSize {
        var ink = PangoRectangle(), logical = PangoRectangle()
        pango_layout_get_extents(layout, &ink, &logical)
        let scale = CGFloat(PANGO_SCALE)
        return NSSize(width: CGFloat(logical.width) / scale, height: CGFloat(logical.height) / scale)
    }

    static func measure(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat? = nil) -> NSSize {
        let layout = make(text, attributes: attributes, width: width, cr: nil)
        defer { g_object_unref(gcast(layout)) }
        return size(of: layout)
    }

    static func metrics(for font: NSFont) -> (ascent: CGFloat, descent: CGFloat) {
        let description = font.makeDescription()
        defer { pango_font_description_free(description) }
        guard let metrics = pango_context_get_metrics(measuringContext, description, nil) else { return (font.pointSize * 0.8, font.pointSize * 0.2) }
        defer { pango_font_metrics_unref(metrics) }
        let scale = CGFloat(PANGO_SCALE)
        return (CGFloat(pango_font_metrics_get_ascent(metrics)) / scale, CGFloat(pango_font_metrics_get_descent(metrics)) / scale)
    }

    /// Draws `text` with its line box's top-left at `rect`'s top-left (in the view's terms), upright
    /// whether the current context is flipped or not, as AppKit draws strings.
    static func draw(_ text: String, attributes: [NSAttributedString.Key: Any], in rect: NSRect, wrapWidth: CGFloat?) {
        guard let current = NSGraphicsContext.current else { return }
        let ctx = current.cgContext
        let cr = ctx._cr
        let layout = make(text, attributes: attributes, width: wrapWidth, cr: cr)
        defer { g_object_unref(gcast(layout)) }
        let size = size(of: layout)
        ctx.saveGState()
        if rect.height > 0, wrapWidth != nil { ctx.clip(to: rect) }
        // Move to the line box's top-left, in a y-down space.
        if current.isFlipped {
            ctx.translateBy(x: rect.minX, y: rect.minY)
        } else {
            let top = rect.height > 0 ? rect.maxY : rect.minY + size.height
            ctx.translateBy(x: rect.minX, y: top)
            ctx.scaleBy(x: 1, y: -1)
        }
        if let background = attributes[.backgroundColor] as? NSColor {
            ctx.setFillColor(red: background.redComponent, green: background.greenComponent,
                             blue: background.blueComponent, alpha: background.alphaComponent)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let color = attributes[.foregroundColor] as? NSColor ?? .black
        cairo_set_source_rgba(cr, color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
        cairo_move_to(cr, 0, 0)
        pango_cairo_show_layout(cr, layout)
        ctx.restoreGState()
    }
}

extension String {
    public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSSize {
        TextLayout.measure(self, attributes: attributes ?? [:])
    }

    public func draw(at point: NSPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        TextLayout.draw(self, attributes: attributes ?? [:], in: NSRect(origin: point, size: .zero), wrapWidth: nil)
    }

    public func draw(in rect: NSRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        TextLayout.draw(self, attributes: attributes ?? [:], in: rect, wrapWidth: rect.width)
    }

    public func draw(with rect: NSRect, options: NSStringDrawingOptions = [], attributes: [NSAttributedString.Key: Any]? = nil,
                     context: NSStringDrawingContext? = nil) {
        draw(in: rect, withAttributes: attributes)
    }

    public func boundingRect(with size: NSSize, options: NSStringDrawingOptions = [],
                             attributes: [NSAttributedString.Key: Any]? = nil, context: NSStringDrawingContext? = nil) -> NSRect {
        let width = size.width > 0 && size.width < 1e6 ? size.width : nil
        return NSRect(origin: .zero, size: TextLayout.measure(self, attributes: attributes ?? [:], width: width))
    }
}

extension NSString {
    public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSSize {
        (self as String).size(withAttributes: attributes)
    }
    public func draw(at point: NSPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        (self as String).draw(at: point, withAttributes: attributes)
    }
    public func draw(in rect: NSRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        (self as String).draw(in: rect, withAttributes: attributes)
    }
    public func boundingRect(with size: NSSize, options: NSStringDrawingOptions = [],
                             attributes: [NSAttributedString.Key: Any]? = nil, context: NSStringDrawingContext? = nil) -> NSRect {
        (self as String).boundingRect(with: size, options: options, attributes: attributes, context: context)
    }
}

extension NSAttributedString {
    /// Attributes of the first run (mixed-attribute strings draw with them throughout).
    /// ponytail: per-run fonts/colours need Pango attribute ranges; add when a view shows mixed runs.
    private var leadingAttributes: [NSAttributedString.Key: Any] {
        length > 0 ? attributes(at: 0, effectiveRange: nil) : [:]
    }

    public func size() -> NSSize { string.size(withAttributes: leadingAttributes) }
    public func draw(at point: NSPoint) { string.draw(at: point, withAttributes: leadingAttributes) }
    public func draw(in rect: NSRect) { string.draw(in: rect, withAttributes: leadingAttributes) }
    public func draw(with rect: NSRect, options: NSStringDrawingOptions = [], context: NSStringDrawingContext? = nil) {
        draw(in: rect)
    }
    public func boundingRect(with size: NSSize, options: NSStringDrawingOptions = [],
                             context: NSStringDrawingContext? = nil) -> NSRect {
        string.boundingRect(with: size, options: options, attributes: leadingAttributes, context: context)
    }
}
