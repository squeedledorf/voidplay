import Foundation
import CCairo

public enum CGPathDrawingMode: Int32, Sendable { case fill, eoFill, stroke, fillStroke, eoFillStroke }

/// A drawing destination: a Cairo context on a bitmap (with Apple's y-up, bottom-left origin) or
/// on a GTK widget (whose host sets the base transform the drawing code expects).
public final class CGContext: @unchecked Sendable {
    /// The Cairo context (`cairo_t *`), for the AppKit text and GTK layers.
    public let _cr: OpaquePointer

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let bitmapInfo: CGBitmapInfo

    private let surface: OpaquePointer?
    /// Bitmap memory in the caller's layout, mirrored from Cairo after each drawing call when
    /// that layout is not Cairo's own. Nil when Cairo draws straight into the caller's memory.
    private let mirror: UnsafeMutableRawPointer?
    private let mirrorLayout: PixelLayout?
    private let ownedMemory: UnsafeMutableRawPointer?

    private struct GState {
        var fill = (r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        var stroke = (r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        var alpha = 1.0
        var interpolation = CGInterpolationQuality.default
        var antialias = true
        var allowsAntialiasing = true
        /// Coverage from `clip(to:mask:)`, in surface space; nil when no mask clip is active.
        var maskClip: MaskClip?
    }

    /// An A8 surface the size of the target, holding the product of every mask clip so far.
    /// A class so saved graphics states share it and the last one to drop it frees it.
    final class MaskClip {
        let surface: OpaquePointer
        init(surface: OpaquePointer) { self.surface = surface }
        deinit { cairo_surface_destroy(surface) }
    }
    private var gstate = GState()
    /// Set when the caller was handed the mirror (`data`) and may have written pixels Cairo has
    /// not seen; the next drawing call or `makeImage` copies them in first.
    private var mirrorMayBeAhead = false
    private var gstack: [GState] = []

    // MARK: Creation

    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int,
                 bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {
        let alpha = bitmapInfo & CGBitmapInfo.alphaInfoMask.rawValue
        let bpp = (space.numberOfComponents == 1 && alpha == CGImageAlphaInfo.none.rawValue)
            || alpha == CGImageAlphaInfo.alphaOnly.rawValue ? 8 : 32
        guard width > 0, height > 0,
              let layout = PixelLayout(bitsPerComponent: bitsPerComponent, bitsPerPixel: bpp, bitmapInfo: bitmapInfo)
        else { return nil }
        let rowBytes = bytesPerRow > 0 ? bytesPerRow : width * layout.bytesPerPixel
        let direct = layout == .cairo && rowBytes % 4 == 0 && rowBytes >= width * 4

        var owned: UnsafeMutableRawPointer?
        var memory = data
        if memory == nil {
            owned = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
            owned!.initializeMemory(as: UInt8.self, repeating: 0, count: rowBytes * height)
            memory = owned
        }

        let surface: OpaquePointer?
        if direct {
            surface = cairo_image_surface_create_for_data(memory!.assumingMemoryBound(to: UInt8.self),
                                                          CAIRO_FORMAT_ARGB32, Int32(width), Int32(height), Int32(rowBytes))
        } else {
            surface = CGImage.makeSurface(width: width, height: height)
            if let surface {
                PixelLayout.convert(from: memory!, layout, srcStride: rowBytes,
                                    to: cairo_image_surface_get_data(surface), .cairo,
                                    dstStride: Int(cairo_image_surface_get_stride(surface)), width: width, height: height)
                cairo_surface_mark_dirty(surface)
            }
        }
        guard let surface, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS, let cr = cairo_create(surface) else {
            owned?.deallocate()
            return nil
        }
        _cr = cr
        self.surface = surface
        self.width = width
        self.height = height
        self.bytesPerRow = rowBytes
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bpp
        self.bitmapInfo = CGBitmapInfo(rawValue: bitmapInfo)
        ownedMemory = owned
        mirror = direct ? nil : memory
        mirrorLayout = direct ? nil : layout
        // Core Graphics bitmap space: origin bottom-left, y up; memory row 0 is the top.
        cairo_translate(cr, 0, Double(height))
        cairo_scale(cr, 1, -1)
    }

    /// Wraps a Cairo context owned by someone else (a GTK draw callback). No base transform.
    public init(_cairo cr: OpaquePointer, width: Int, height: Int) {
        _cr = cairo_reference(cr)
        surface = nil
        mirror = nil
        mirrorLayout = nil
        ownedMemory = nil
        self.width = width
        self.height = height
        bytesPerRow = width * 4
        bitsPerComponent = 8
        bitsPerPixel = 32
        bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    deinit {
        cairo_destroy(_cr)
        if let surface { cairo_surface_destroy(surface) }
        ownedMemory?.deallocate()
    }

    /// Bitmap memory, in the layout the context was created with.
    public var data: UnsafeMutableRawPointer? {
        if let mirror {
            if cairoAhead { syncMirrorFromCairo() }
            mirrorMayBeAhead = true
            return mirror
        }
        guard let surface else { return nil }
        cairo_surface_flush(surface)
        return UnsafeMutableRawPointer(cairo_image_surface_get_data(surface))
    }

    /// Copies Cairo's pixels into the caller's memory when it uses another layout.
    /// ponytail: converts the whole bitmap per drawing call; fine for the small sampling contexts
    /// that use foreign layouts, needs a dirty rect if a big one shows up in a profile.
    /// Brings pixels the caller wrote through `data` into Cairo before Cairo draws or is read.
    private func willDraw() {
        guard mirrorMayBeAhead, let mirror, let mirrorLayout, let surface else { return }
        mirrorMayBeAhead = false
        cairo_surface_flush(surface)
        PixelLayout.convert(from: mirror, mirrorLayout, srcStride: bytesPerRow,
                            to: cairo_image_surface_get_data(surface), .cairo,
                            dstStride: Int(cairo_image_surface_get_stride(surface)), width: width, height: height)
        cairo_surface_mark_dirty(surface)
    }

    private func didDraw() {
        guard mirror != nil else { return }
        // Memory we own is only reachable through `data`, so it is brought up to date there,
        // once, instead of after every drawing call (a full-bitmap conversion each time).
        if ownedMemory != nil { cairoAhead = true; return }
        syncMirrorFromCairo()
    }

    /// Set when Cairo has pixels the mirror (owned memory) does not yet show.
    private var cairoAhead = false

    private func syncMirrorFromCairo() {
        guard let mirror, let mirrorLayout, let surface else { return }
        cairoAhead = false
        cairo_surface_flush(surface)
        PixelLayout.convert(from: cairo_image_surface_get_data(surface), .cairo,
                            srcStride: Int(cairo_image_surface_get_stride(surface)),
                            to: mirror, mirrorLayout, dstStride: bytesPerRow, width: width, height: height)
    }

    public func flush() {
        cairo_surface_flush(cairo_get_target(_cr))
        didDraw()
    }

    public func makeImage() -> CGImage? {
        willDraw()
        let target = cairo_get_target(_cr)
        cairo_surface_flush(target)
        guard cairo_surface_get_type(target) == CAIRO_SURFACE_TYPE_IMAGE,
              let copy = CGImage.makeSurface(width: width, height: height) else { return nil }
        let cr = cairo_create(copy)
        cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
        cairo_set_source_surface(cr, target, 0, 0)
        cairo_paint(cr)
        cairo_destroy(cr)
        return CGImage(_surface: copy)
    }

    // MARK: Graphics state

    public func saveGState() {
        cairo_save(_cr)
        gstack.append(gstate)
    }

    public func restoreGState() {
        cairo_restore(_cr)
        if let saved = gstack.popLast() { gstate = saved }
    }

    public func translateBy(x: CGFloat, y: CGFloat) { cairo_translate(_cr, Double(x), Double(y)) }
    public func scaleBy(x: CGFloat, y: CGFloat) { cairo_scale(_cr, Double(x), Double(y)) }
    public func rotate(by angle: CGFloat) { cairo_rotate(_cr, Double(angle)) }

    public func concatenate(_ t: CGAffineTransform) {
        var m = cairo_matrix_t(xx: t.a, yx: t.b, xy: t.c, yy: t.d, x0: t.tx, y0: t.ty)
        cairo_transform(_cr, &m)
    }

    public var ctm: CGAffineTransform {
        var m = cairo_matrix_t()
        cairo_get_matrix(_cr, &m)
        return CGAffineTransform(a: m.xx, b: m.yx, c: m.xy, d: m.yy, tx: m.x0, ty: m.y0)
    }

    public var userSpaceToDeviceSpaceTransform: CGAffineTransform { ctm }

    public func convertToDeviceSpace(_ point: CGPoint) -> CGPoint { point.applying(ctm) }
    public func convertToUserSpace(_ point: CGPoint) -> CGPoint { point.applying(ctm.inverted()) }
    public func convertToDeviceSpace(_ rect: CGRect) -> CGRect { rect.applying(ctm) }
    public func convertToUserSpace(_ rect: CGRect) -> CGRect { rect.applying(ctm.inverted()) }

    public func setFillColor(_ color: CGColor) {
        let c = color.rgba
        gstate.fill = (c.r, c.g, c.b, c.a)
    }

    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        gstate.fill = (red, green, blue, alpha)
    }

    public func setFillColor(gray: CGFloat, alpha: CGFloat) { gstate.fill = (gray, gray, gray, alpha) }

    /// Bitmap contexts here are all device RGB (or alpha-only, which has none).
    public var colorSpace: CGColorSpace? { bitsPerPixel == 8 ? nil : CGColorSpaceCreateDeviceRGB() }

    /// The current fill colour (for CoreText's draw-in-context-colour lines).
    public var _fillRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { (gstate.fill.r, gstate.fill.g, gstate.fill.b, gstate.fill.a) }

    public func setStrokeColor(_ color: CGColor) {
        let c = color.rgba
        gstate.stroke = (c.r, c.g, c.b, c.a)
    }

    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        gstate.stroke = (red, green, blue, alpha)
    }

    public func setStrokeColor(gray: CGFloat, alpha: CGFloat) { gstate.stroke = (gray, gray, gray, alpha) }

    public func setAlpha(_ alpha: CGFloat) { gstate.alpha = Double(alpha) }
    public func setLineWidth(_ width: CGFloat) { cairo_set_line_width(_cr, Double(width)) }
    public func setLineCap(_ cap: CGLineCap) { cairo_set_line_cap(_cr, cairo_line_cap_t(UInt32(cap.rawValue))) }
    public func setLineJoin(_ join: CGLineJoin) { cairo_set_line_join(_cr, cairo_line_join_t(UInt32(join.rawValue))) }
    public func setMiterLimit(_ limit: CGFloat) { cairo_set_miter_limit(_cr, Double(limit)) }

    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) {
        cairo_set_dash(_cr, lengths.map(Double.init), Int32(lengths.count), Double(phase))
    }

    /// Where text drawn next starts (CoreText's CTLineDraw), in user space.
    public var textPosition: CGPoint = .zero
    /// Font smoothing is Cairo's font options' business; text follows `setShouldAntialias`.
    public func setShouldSmoothFonts(_ value: Bool) {}
    /// Whether text drawn now should be antialiased (for the CoreText stand-in).
    public var _textAntialiased: Bool { gstate.antialias && gstate.allowsAntialiasing }
    /// Called by drawing done straight on `_cr` from other stand-in modules (CoreText).
    public func _didDrawExternally() { didDraw() }
    public func _willDrawExternally() { willDraw() }

    public func setShouldAntialias(_ value: Bool) {
        gstate.antialias = value
        cairo_set_antialias(_cr, value && gstate.allowsAntialiasing ? CAIRO_ANTIALIAS_DEFAULT : CAIRO_ANTIALIAS_NONE)
    }

    public func setAllowsAntialiasing(_ value: Bool) {
        gstate.allowsAntialiasing = value
        setShouldAntialias(gstate.antialias)
    }

    public var interpolationQuality: CGInterpolationQuality {
        get { gstate.interpolation }
        set { gstate.interpolation = newValue }
    }

    public func setBlendMode(_ mode: CGBlendMode) {
        let op: cairo_operator_t
        switch mode {
        case .normal: op = CAIRO_OPERATOR_OVER
        case .multiply: op = CAIRO_OPERATOR_MULTIPLY
        case .screen: op = CAIRO_OPERATOR_SCREEN
        case .overlay: op = CAIRO_OPERATOR_OVERLAY
        case .darken: op = CAIRO_OPERATOR_DARKEN
        case .lighten: op = CAIRO_OPERATOR_LIGHTEN
        case .colorDodge: op = CAIRO_OPERATOR_COLOR_DODGE
        case .colorBurn: op = CAIRO_OPERATOR_COLOR_BURN
        case .softLight: op = CAIRO_OPERATOR_SOFT_LIGHT
        case .hardLight: op = CAIRO_OPERATOR_HARD_LIGHT
        case .difference: op = CAIRO_OPERATOR_DIFFERENCE
        case .exclusion: op = CAIRO_OPERATOR_EXCLUSION
        case .hue: op = CAIRO_OPERATOR_HSL_HUE
        case .saturation: op = CAIRO_OPERATOR_HSL_SATURATION
        case .color: op = CAIRO_OPERATOR_HSL_COLOR
        case .luminosity: op = CAIRO_OPERATOR_HSL_LUMINOSITY
        case .clear: op = CAIRO_OPERATOR_CLEAR
        case .copy: op = CAIRO_OPERATOR_SOURCE
        case .sourceIn: op = CAIRO_OPERATOR_IN
        case .sourceOut: op = CAIRO_OPERATOR_OUT
        case .sourceAtop: op = CAIRO_OPERATOR_ATOP
        case .destinationOver: op = CAIRO_OPERATOR_DEST_OVER
        case .destinationIn: op = CAIRO_OPERATOR_DEST_IN
        case .destinationOut: op = CAIRO_OPERATOR_DEST_OUT
        case .destinationAtop: op = CAIRO_OPERATOR_DEST_ATOP
        case .xor: op = CAIRO_OPERATOR_XOR
        case .plusLighter, .plusDarker: op = CAIRO_OPERATOR_ADD
        }
        cairo_set_operator(_cr, op)
    }

    /// Core Graphics shadows have no Cairo equivalent; drawing proceeds without one.
    /// ponytail: soft shadows (blur pass on a group) only if a skin visibly needs them.
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor? = nil) {}

    public func beginTransparencyLayer(auxiliaryInfo: Any?) { cairo_push_group(_cr) }

    public func endTransparencyLayer() {
        willDraw()
        cairo_pop_group_to_source(_cr)
        masked { cairo_paint_with_alpha(_cr, gstate.alpha) }
        didDraw()
    }

    // MARK: Paths

    public func beginPath() { cairo_new_path(_cr) }
    public func closePath() { cairo_close_path(_cr) }
    public func move(to point: CGPoint) { cairo_move_to(_cr, Double(point.x), Double(point.y)) }
    public func addLine(to point: CGPoint) { cairo_line_to(_cr, Double(point.x), Double(point.y)) }

    public func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        points.dropFirst().forEach(addLine(to:))
    }

    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        cairo_curve_to(_cr, control1.x, control1.y, control2.x, control2.y, end.x, end.y)
    }

    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        var x = 0.0, y = 0.0
        cairo_get_current_point(_cr, &x, &y)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: y))
        path.addQuadCurve(to: end, control: control)
        path.elements.removeFirst()
        path.replay(on: _cr)
    }

    /// Cairo works in 24.8 fixed point; "infinite" rects (upstream clips text to a ±∞/2-tall band)
    /// overflow it into an empty path, so coordinates are clamped to a range no surface reaches.
    public func addRect(_ rect: CGRect) {
        let limit = 1_000_000.0
        let x0 = min(max(Double(rect.minX), -limit), limit), x1 = min(max(Double(rect.maxX), -limit), limit)
        let y0 = min(max(Double(rect.minY), -limit), limit), y1 = min(max(Double(rect.maxY), -limit), limit)
        cairo_rectangle(_cr, x0, y0, x1 - x0, y1 - y0)
    }
    public func addRects(_ rects: [CGRect]) { rects.forEach(addRect) }

    public func addEllipse(in rect: CGRect) {
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        path.replay(on: _cr)
    }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
        if cairo_has_current_point(_cr) != 0, case .move(let p)? = path.elements.first {
            path.elements[0] = .line(p)
        }
        path.replay(on: _cr)
    }

    public func addPath(_ path: CGPath) { path.replay(on: _cr) }

    /// Cairo cannot turn a stroke outline into a path, so the path becomes empty: a following
    /// clip() hides everything and the stroke-shaped effect (a hairline highlight) is skipped.
    /// ponytail: draw such highlights by stroking with a gradient source if a skin needs them.
    public func replacePathWithStrokedPath() { cairo_new_path(_cr) }

    public var isPathEmpty: Bool {
        guard let path = cairo_copy_path(_cr) else { return true }
        defer { cairo_path_destroy(path) }
        return path.pointee.num_data == 0
    }

    public var currentPointOfPath: CGPoint {
        var x = 0.0, y = 0.0
        cairo_get_current_point(_cr, &x, &y)
        return CGPoint(x: x, y: y)
    }

    public var boundingBoxOfPath: CGRect {
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        cairo_path_extents(_cr, &x1, &y1, &x2, &y2)
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    // MARK: Painting

    private func useFill() {
        let c = gstate.fill
        cairo_set_source_rgba(_cr, c.r, c.g, c.b, c.a * gstate.alpha)
    }

    private func useStroke() {
        let c = gstate.stroke
        cairo_set_source_rgba(_cr, c.r, c.g, c.b, c.a * gstate.alpha)
    }

    private func setRule(_ rule: CGPathFillRule) {
        cairo_set_fill_rule(_cr, rule == .evenOdd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
    }

    public func fillPath(using rule: CGPathFillRule = .winding) {
        willDraw()
        setRule(rule)
        useFill()
        masked { cairo_fill(_cr) }
        didDraw()
    }

    public func strokePath() {
        willDraw()
        useStroke()
        masked { cairo_stroke(_cr) }
        didDraw()
    }

    public func drawPath(using mode: CGPathDrawingMode) {
        setRule(mode == .eoFill || mode == .eoFillStroke ? .evenOdd : .winding)
        switch mode {
        case .fill, .eoFill:
            useFill(); masked { cairo_fill(_cr) }
        case .stroke:
            useStroke(); masked { cairo_stroke(_cr) }
        case .fillStroke, .eoFillStroke:
            useFill(); masked { cairo_fill_preserve(_cr) }
            useStroke(); masked { cairo_stroke(_cr) }
        }
        didDraw()
    }

    public func fill(_ rect: CGRect) { fill([rect]) }

    public func fill(_ rects: [CGRect]) {
        willDraw()
        cairo_new_path(_cr)
        rects.forEach(addRect)
        fillPath()
    }

    public func fillEllipse(in rect: CGRect) {
        cairo_new_path(_cr)
        addEllipse(in: rect)
        fillPath()
    }

    public func stroke(_ rect: CGRect) {
        cairo_new_path(_cr)
        addRect(rect)
        strokePath()
    }

    public func stroke(_ rect: CGRect, width: CGFloat) {
        cairo_save(_cr)
        cairo_set_line_width(_cr, Double(width))
        stroke(rect)
        cairo_restore(_cr)
    }

    public func strokeEllipse(in rect: CGRect) {
        cairo_new_path(_cr)
        addEllipse(in: rect)
        strokePath()
    }

    public func strokeLineSegments(between points: [CGPoint]) {
        cairo_new_path(_cr)
        var i = 0
        while i + 1 < points.count {
            move(to: points[i])
            addLine(to: points[i + 1])
            i += 2
        }
        strokePath()
    }

    public func clear(_ rect: CGRect) {
        willDraw()
        cairo_save(_cr)
        cairo_set_operator(_cr, CAIRO_OPERATOR_CLEAR)
        cairo_new_path(_cr)
        addRect(rect)
        masked { cairo_fill(_cr) }
        cairo_restore(_cr)
        didDraw()
    }

    // MARK: Clipping

    public func clip(using rule: CGPathFillRule = .winding) {
        setRule(rule)
        cairo_clip(_cr)
    }

    public func clip(to rect: CGRect) { clip(to: [rect]) }

    public func clip(to rects: [CGRect]) {
        cairo_new_path(_cr)
        rects.forEach(addRect)
        cairo_clip(_cr)
    }

    /// Clips to `rect`, using `mask` as coverage drawn as Core Graphics would place it: a mask
    /// without transparency (DeviceGray) clips by brightness (white keeps), one with alpha by alpha.
    /// Cairo has no image clip, so the coverage is rendered once into a surface-space A8 mask kept
    /// in the graphics state, and every later paint goes through it (`masked`).
    public func clip(to rect: CGRect, mask: CGImage) {
        cairo_new_path(_cr)
        addRect(rect)
        cairo_clip(_cr)
        guard let coverage = Self.coverage(of: mask) else { return }
        defer { cairo_surface_destroy(coverage) }
        let target = cairo_get_target(_cr)
        var sx = 1.0, sy = 1.0
        cairo_surface_get_device_scale(target, &sx, &sy)
        let w = Int32((Double(width) * sx).rounded(.up)), h = Int32((Double(height) * sy).rounded(.up))
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_A8, w, h),
              cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else { return }
        cairo_surface_set_device_scale(surface, sx, sy)
        let cr = cairo_create(surface)!
        var matrix = cairo_matrix_t()
        cairo_get_matrix(_cr, &matrix)
        cairo_set_matrix(cr, &matrix)
        cairo_translate(cr, rect.minX, rect.maxY)
        cairo_scale(cr, rect.width / Double(mask.width), -rect.height / Double(mask.height))
        cairo_set_source_surface(cr, coverage, 0, 0)
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD)
        cairo_rectangle(cr, 0, 0, Double(mask.width), Double(mask.height))
        cairo_fill(cr)
        if let previous = gstate.maskClip {
            // Nested clips intersect: keep only what the earlier mask kept too.
            cairo_identity_matrix(cr)
            cairo_set_operator(cr, CAIRO_OPERATOR_IN)
            cairo_set_source_surface(cr, previous.surface, 0, 0)
            cairo_paint(cr)
        }
        cairo_destroy(cr)
        cairo_surface_flush(surface)
        gstate.maskClip = MaskClip(surface: surface)
    }

    /// The mask's coverage as an A8 surface: alpha when it has any transparency, else brightness.
    private static func coverage(of mask: CGImage) -> OpaquePointer? {
        let source = mask._surface
        cairo_surface_flush(source)
        guard let data = cairo_image_surface_get_data(source),
              let out = cairo_image_surface_create(CAIRO_FORMAT_A8, Int32(mask.width), Int32(mask.height)),
              let outData = cairo_image_surface_get_data(out) else { return nil }
        let stride = Int(cairo_image_surface_get_stride(source)), outStride = Int(cairo_image_surface_get_stride(out))
        var hasAlpha = false
        for y in 0..<mask.height where !hasAlpha {
            for x in 0..<mask.width where data[y * stride + x * 4 + 3] < 255 { hasAlpha = true; break }
        }
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let p = y * stride + x * 4  // B, G, R, A (premultiplied)
                outData[y * outStride + x] = hasAlpha ? data[p + 3] : data[p + 2]
            }
        }
        cairo_surface_mark_dirty(out)
        return out
    }

    /// Runs one Cairo paint operation through the active mask clip, if any.
    private func masked(_ paint: () -> Void) {
        guard let mask = gstate.maskClip else { paint(); return }
        cairo_push_group(_cr)
        paint()
        // The group becomes the source under the current matrix (a source is locked to the user
        // space it was set in); only the mask, which lives in surface space, uses identity.
        cairo_pop_group_to_source(_cr)
        cairo_save(_cr)
        cairo_identity_matrix(_cr)
        cairo_mask_surface(_cr, mask.surface, 0, 0)
        cairo_restore(_cr)
    }

    /// For drawing done straight on `_cr` by other stand-in modules (CoreText).
    public func _masked(_ paint: () -> Void) { masked(paint) }

    public func resetClip() { cairo_reset_clip(_cr) }

    public var boundingBoxOfClipPath: CGRect {
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        cairo_clip_extents(_cr, &x1, &y1, &x2, &y2)
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    // MARK: Images

    /// Paints `image` so its top row lands at `rect.maxY`, as Core Graphics does: upright in a
    /// y-up space, upside down in a flipped one (callers that flip compensate, as on macOS).
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        willDraw()
        if byTiling {
            cairo_save(_cr)
            cairo_new_path(_cr)
            cairo_rectangle(_cr, rect.minX, rect.minY, rect.width, rect.height)
            cairo_clip(_cr)
            let clip = boundingBoxOfClipPath
            var y = rect.minY
            while y < clip.maxY {
                var x = rect.minX
                while x < clip.maxX {
                    imagePaint(image, in: CGRect(x: x, y: y, width: rect.width, height: rect.height), alpha: gstate.alpha)
                    x += max(1, rect.width)
                }
                y += max(1, rect.height)
            }
            cairo_restore(_cr)
        } else {
            imagePaint(image, in: rect, alpha: gstate.alpha)
        }
        didDraw()
    }

    private func imagePaint(_ image: CGImage, in rect: CGRect, alpha: Double) {
        guard rect.width != 0, rect.height != 0, image.width > 0, image.height > 0 else { return }
        cairo_save(_cr)
        cairo_translate(_cr, rect.minX, rect.maxY)
        cairo_scale(_cr, rect.width / Double(image.width), -rect.height / Double(image.height))
        cairo_set_source_surface(_cr, image._surface, 0, 0)
        let pattern = cairo_get_source(_cr)
        let filter: cairo_filter_t
        switch gstate.interpolation {
        case .none: filter = CAIRO_FILTER_NEAREST
        case .low: filter = CAIRO_FILTER_FAST
        case .high: filter = CAIRO_FILTER_BEST
        default: filter = image.shouldInterpolate ? CAIRO_FILTER_GOOD : CAIRO_FILTER_NEAREST
        }
        cairo_pattern_set_filter(pattern, filter)
        cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD)
        cairo_new_path(_cr)
        cairo_rectangle(_cr, 0, 0, Double(image.width), Double(image.height))
        cairo_clip(_cr)
        masked { cairo_paint_with_alpha(_cr, alpha) }
        cairo_restore(_cr)
    }
}
