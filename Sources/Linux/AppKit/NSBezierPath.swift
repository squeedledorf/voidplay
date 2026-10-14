import Foundation
import CoreGraphics

/// A path that draws itself into the current graphics context.
open class NSBezierPath {
    public enum LineCapStyle: UInt, Sendable { case butt, round, square }
    public enum LineJoinStyle: UInt, Sendable { case miter, round, bevel }
    public enum WindingRule: UInt, Sendable { case nonZero, evenOdd }

    public private(set) var cgPath = CGMutablePath()
    open var lineWidth: CGFloat = 1
    open var lineCapStyle: LineCapStyle = .butt
    open var lineJoinStyle: LineJoinStyle = .miter
    open var windingRule: WindingRule = .nonZero
    private var dash: (phase: CGFloat, lengths: [CGFloat])?

    public init() {}
    public convenience init(rect: NSRect) { self.init(); appendRect(rect) }
    public convenience init(ovalIn rect: NSRect) { self.init(); cgPath.addEllipse(in: rect) }
    public convenience init(roundedRect rect: NSRect, xRadius: CGFloat, yRadius: CGFloat) {
        self.init()
        cgPath.addRoundedRect(in: rect, cornerWidth: xRadius, cornerHeight: yRadius)
    }

    open var isEmpty: Bool { cgPath.isEmpty }
    open var bounds: NSRect { cgPath.boundingBox }
    open var currentPoint: NSPoint { cgPath.currentPoint }

    open func move(to point: NSPoint) { cgPath.move(to: point) }
    open func line(to point: NSPoint) { cgPath.addLine(to: point) }
    open func relativeLine(to point: NSPoint) {
        let c = currentPoint
        cgPath.addLine(to: NSPoint(x: c.x + point.x, y: c.y + point.y))
    }
    open func curve(to end: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) {
        cgPath.addCurve(to: end, control1: controlPoint1, control2: controlPoint2)
    }
    open func close() { cgPath.closeSubpath() }
    open func appendRect(_ rect: NSRect) { cgPath.addRect(rect) }
    open func appendOval(in rect: NSRect) { cgPath.addEllipse(in: rect) }
    open func appendRoundedRect(_ rect: NSRect, xRadius: CGFloat, yRadius: CGFloat) {
        cgPath.addRoundedRect(in: rect, cornerWidth: xRadius, cornerHeight: yRadius)
    }
    open func append(_ path: NSBezierPath) { cgPath.addPath(path.cgPath) }
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat,
                        clockwise: Bool = false) {
        cgPath.addArc(center: center, radius: radius, startAngle: startAngle * .pi / 180, endAngle: endAngle * .pi / 180,
                      clockwise: clockwise)
    }
    open func removeAllPoints() { cgPath = CGMutablePath() }
    open func setLineDash(_ pattern: UnsafePointer<CGFloat>?, count: Int, phase: CGFloat) {
        dash = pattern.map { (phase, Array(UnsafeBufferPointer(start: $0, count: count))) }
    }

    open func transform(using transform: AffineTransform) {
        let t = CGAffineTransform(a: transform.m11, b: transform.m12, c: transform.m21, d: transform.m22,
                                  tx: transform.tX, ty: transform.tY)
        let moved = CGMutablePath()
        moved.addPath(cgPath, transform: t)
        cgPath = moved
    }

    open func contains(_ point: NSPoint) -> Bool { bounds.contains(point) }

    private func prepare(_ ctx: CGContext) {
        ctx.beginPath()
        ctx.addPath(cgPath)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(CGLineCap(rawValue: Int32(lineCapStyle.rawValue)) ?? .butt)
        ctx.setLineJoin(CGLineJoin(rawValue: Int32(lineJoinStyle.rawValue)) ?? .miter)
        if let dash { ctx.setLineDash(phase: dash.phase, lengths: dash.lengths) }
    }

    open func fill() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); prepare(ctx); ctx.fillPath(using: windingRule == .evenOdd ? .evenOdd : .winding); ctx.restoreGState()
    }

    open func stroke() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); prepare(ctx); ctx.strokePath(); ctx.restoreGState()
    }

    open func addClip() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.beginPath(); ctx.addPath(cgPath); ctx.clip(using: windingRule == .evenOdd ? .evenOdd : .winding)
    }

    open func setClip() { addClip() }

    public static func fill(_ rect: NSRect) { NSBezierPath(rect: rect).fill() }
    public static func stroke(_ rect: NSRect) { NSBezierPath(rect: rect).stroke() }
    public static func strokeLine(from a: NSPoint, to b: NSPoint) {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.stroke()
    }
    public static func clip(_ rect: NSRect) { NSBezierPath(rect: rect).addClip() }
    public static var defaultLineWidth: CGFloat = 1
}

/// Colour ramp drawn as a Cairo gradient through Core Graphics.
open class NSGradient {
    private let colors: [NSColor]
    private let locations: [CGFloat]

    public convenience init?(starting: NSColor, ending: NSColor) { self.init(colors: [starting, ending]) }

    public init?(colors: [NSColor]) {
        guard colors.count >= 2 else { return nil }
        self.colors = colors
        locations = colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
    }

    public init?(colors: [NSColor], atLocations locations: UnsafePointer<CGFloat>?, colorSpace: NSColorSpace) {
        guard colors.count >= 2 else { return nil }
        self.colors = colors
        self.locations = locations.map { Array(UnsafeBufferPointer(start: $0, count: colors.count)) }
            ?? colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
    }

    public convenience init?(colorsAndLocations pairs: (NSColor, CGFloat)...) {
        var locations = pairs.map(\.1)
        self.init(colors: pairs.map(\.0), atLocations: &locations, colorSpace: .sRGB)
    }

    private var cgGradient: CGGradient? {
        var locs = locations
        return CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor), locations: &locs)
    }

    /// `angle` in degrees, 0 = left to right, 90 = bottom to top (AppKit's convention).
    open func draw(in rect: NSRect, angle: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let gradient = cgGradient else { return }
        let radians = angle * .pi / 180
        let dx = cos(radians) * rect.width / 2, dy = sin(radians) * rect.height / 2
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX - dx, y: rect.midY - dy),
                               end: CGPoint(x: rect.midX + dx, y: rect.midY + dy),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    open func draw(in path: NSBezierPath, angle: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        path.addClip()
        draw(in: path.bounds, angle: angle)
        ctx.restoreGState()
    }

    open func draw(from start: NSPoint, to end: NSPoint, options: Int) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let gradient = cgGradient else { return }
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

public final class NSColorSpace: @unchecked Sendable {
    public let localizedName: String?
    init(_ name: String) { localizedName = name }
    public static let sRGB = NSColorSpace("sRGB IEC61966-2.1")
    public static let deviceRGB = NSColorSpace("Device RGB")
    public static let genericRGB = NSColorSpace("Generic RGB")
}

/// What a display can show: 8-bit sRGB on Linux (no colour management or HDR here).
public enum NSDisplayGamut: Sendable { case sRGB, p3 }

extension NSWindow {
    public struct Depth: RawRepresentable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }
        public static let twentyfourBitRGB = Depth(rawValue: 0x208)
    }
    public var depthLimit: Depth { .twentyfourBitRGB }
    public var hasDynamicDepthLimit: Bool { false }
    public func canRepresent(_ gamut: NSDisplayGamut) -> Bool { gamut == .sRGB }
    public var colorSpace: NSColorSpace? { .sRGB }
}

extension NSScreen {
    public var maximumExtendedDynamicRangeColorComponentValue: CGFloat { 1 }
    public var maximumPotentialExtendedDynamicRangeColorComponentValue: CGFloat { 1 }
    public var colorSpace: NSColorSpace? { .sRGB }
}

/// Accessibility objects exist for the AT-SPI bridge to come; today they hold their values only.
open class NSAccessibilityElement: NSObject {
    public override init() { super.init() }
    open func setAccessibilityLabel(_ label: String?) {}
    open func setAccessibilityRole(_ role: NSAccessibility.Role?) {}
    open func setAccessibilityFrame(_ frame: NSRect) {}
    open func setAccessibilityFrameInParentSpace(_ frame: NSRect) {}
    open func setAccessibilityParent(_ parent: Any?) {}
    open func setAccessibilityIdentifier(_ identifier: String?) {}
    open func setAccessibilityValue(_ value: Any?) {}
    open func setAccessibilityEnabled(_ enabled: Bool) {}
    open func setAccessibilityHelp(_ help: String?) {}
}
