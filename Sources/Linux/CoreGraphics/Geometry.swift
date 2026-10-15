// Linux stand-in for the slice of CoreGraphics the skin renderers use, drawn with Cairo.
// Semantics follow Apple's: a y-up user space, images painted with their top at a rect's maxY,
// premultiplied colour. The GTK layer sets the base transform each view expects.
@_exported import Foundation

public struct CGAffineTransform: Equatable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public init() { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public init(translationX x: CGFloat, y: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y) }
    public init(scaleX x: CGFloat, y: CGFloat) { self.init(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) {
        self.init(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0)
    }

    public static let identity = CGAffineTransform()
    public var isIdentity: Bool { self == .identity }

    /// `self` applied first, then `t2` (Apple's order).
    public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: a * t2.a + b * t2.c, b: a * t2.b + b * t2.d,
                          c: c * t2.a + d * t2.c, d: c * t2.b + d * t2.d,
                          tx: tx * t2.a + ty * t2.c + t2.tx, ty: tx * t2.b + ty * t2.d + t2.ty)
    }

    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).concatenating(self)
    }

    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: x, y: y).concatenating(self)
    }

    public func rotated(by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).concatenating(self)
    }

    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        guard det != 0 else { return self }
        return CGAffineTransform(a: d / det, b: -b / det, c: -c / det, d: a / det,
                                 tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: t.a * width + t.c * height, height: t.b * width + t.d * height)
    }
}

extension CGRect {
    /// Bounding box of the transformed corners, as Apple returns.
    public func applying(_ t: CGAffineTransform) -> CGRect {
        let corners = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                       CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)].map { $0.applying(t) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

public enum CGLineCap: Int32, Sendable { case butt, round, square }
public enum CGLineJoin: Int32, Sendable { case miter, round, bevel }
public enum CGPathFillRule: Int, Sendable { case winding, evenOdd }
public enum CGInterpolationQuality: Int32, Sendable { case `default`, none, low, medium, high }

public enum CGBlendMode: Int32, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight,
         difference, exclusion, hue, saturation, color, luminosity, clear, copy, sourceIn, sourceOut,
         sourceAtop, destinationOver, destinationIn, destinationOut, destinationAtop, xor,
         plusDarker, plusLighter
}

/// A display's id (Quartz Display Services); nothing on Linux hands one out.
public typealias CGDirectDisplayID = UInt32
