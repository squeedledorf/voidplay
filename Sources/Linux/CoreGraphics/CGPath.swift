import Foundation
import CCairo

/// A recorded path, replayed onto Cairo when a context fills, strokes or clips it.
public class CGPath: @unchecked Sendable {
    enum Element {
        case move(CGPoint)
        case line(CGPoint)
        case quad(CGPoint, CGPoint)
        case cubic(CGPoint, CGPoint, CGPoint)
        case close
    }

    var elements: [Element] = []

    init(elements: [Element]) { self.elements = elements }

    public convenience init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        let path = CGMutablePath()
        path.addRect(rect, transform: transform?.pointee ?? .identity)
        self.init(elements: path.elements)
    }

    public convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        let path = CGMutablePath()
        path.addEllipse(in: rect, transform: transform?.pointee ?? .identity)
        self.init(elements: path.elements)
    }

    public convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat,
                            transform: UnsafePointer<CGAffineTransform>?) {
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight,
                            transform: transform?.pointee ?? .identity)
        self.init(elements: path.elements)
    }

    public var isEmpty: Bool { elements.isEmpty }

    public var currentPoint: CGPoint {
        for element in elements.reversed() {
            switch element {
            case .move(let p), .line(let p), .quad(_, let p), .cubic(_, _, let p): return p
            case .close: continue
            }
        }
        return .zero
    }

    public var boundingBox: CGRect {
        var points: [CGPoint] = []
        for element in elements {
            switch element {
            case .move(let p), .line(let p): points.append(p)
            case .quad(let c, let p): points += [c, p]
            case .cubic(let c1, let c2, let p): points += [c1, c2, p]
            case .close: break
            }
        }
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    public func copy() -> CGPath? { CGPath(elements: elements) }
    public func mutableCopy() -> CGMutablePath? { CGMutablePath(elements: elements) }

    /// Emits the path into `cr` in its current user space.
    func replay(on cr: OpaquePointer) {
        var last = CGPoint.zero
        for element in elements {
            switch element {
            case .move(let p): cairo_move_to(cr, p.x, p.y); last = p
            case .line(let p): cairo_line_to(cr, p.x, p.y); last = p
            case .quad(let c, let p):
                // Elevate to cubic: Cairo has no quadratic segments.
                let c1 = CGPoint(x: last.x + 2 / 3 * (c.x - last.x), y: last.y + 2 / 3 * (c.y - last.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, p.x, p.y); last = p
            case .cubic(let c1, let c2, let p): cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, p.x, p.y); last = p
            case .close: cairo_close_path(cr)
            }
        }
    }
}

public final class CGMutablePath: CGPath, @unchecked Sendable {
    public init() { super.init(elements: []) }
    override init(elements: [Element]) { super.init(elements: elements) }

    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) {
        elements.append(.move(point.applying(transform)))
    }

    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) {
        elements.append(.line(point.applying(transform)))
    }

    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) {
        guard let first = points.first else { return }
        move(to: first, transform: transform)
        for point in points.dropFirst() { addLine(to: point, transform: transform) }
    }

    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        elements.append(.quad(control.applying(transform), end.applying(transform)))
    }

    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint,
                         transform: CGAffineTransform = .identity) {
        elements.append(.cubic(control1.applying(transform), control2.applying(transform), end.applying(transform)))
    }

    public func closeSubpath() { elements.append(.close) }

    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        move(to: CGPoint(x: rect.minX, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY), transform: transform)
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY), transform: transform)
        closeSubpath()
    }

    public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        rects.forEach { addRect($0, transform: transform) }
    }

    /// Four cubic quarter-arcs (kappa ≈ 0.5523), as Core Graphics builds ellipses.
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let k: CGFloat = 0.5522847498
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        move(to: CGPoint(x: cx + rx, y: cy), transform: transform)
        addCurve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + k * ry),
                 control2: CGPoint(x: cx + k * rx, y: cy + ry), transform: transform)
        addCurve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - k * rx, y: cy + ry),
                 control2: CGPoint(x: cx - rx, y: cy + k * ry), transform: transform)
        addCurve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - k * ry),
                 control2: CGPoint(x: cx - k * rx, y: cy - ry), transform: transform)
        addCurve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + k * rx, y: cy - ry),
                 control2: CGPoint(x: cx + rx, y: cy - k * ry), transform: transform)
        closeSubpath()
    }

    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat,
                               transform: CGAffineTransform = .identity) {
        let rx = min(cornerWidth, rect.width / 2), ry = min(cornerHeight, rect.height / 2)
        guard rx > 0, ry > 0 else { addRect(rect, transform: transform); return }
        let k: CGFloat = 0.5522847498
        move(to: CGPoint(x: rect.minX + rx, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX - rx, y: rect.minY), transform: transform)
        addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                 control1: CGPoint(x: rect.maxX - rx + k * rx, y: rect.minY),
                 control2: CGPoint(x: rect.maxX, y: rect.minY + ry - k * ry), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry), transform: transform)
        addCurve(to: CGPoint(x: rect.maxX - rx, y: rect.maxY),
                 control1: CGPoint(x: rect.maxX, y: rect.maxY - ry + k * ry),
                 control2: CGPoint(x: rect.maxX - rx + k * rx, y: rect.maxY), transform: transform)
        addLine(to: CGPoint(x: rect.minX + rx, y: rect.maxY), transform: transform)
        addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - ry),
                 control1: CGPoint(x: rect.minX + rx - k * rx, y: rect.maxY),
                 control2: CGPoint(x: rect.minX, y: rect.maxY - ry + k * ry), transform: transform)
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + ry), transform: transform)
        addCurve(to: CGPoint(x: rect.minX + rx, y: rect.minY),
                 control1: CGPoint(x: rect.minX, y: rect.minY + ry - k * ry),
                 control2: CGPoint(x: rect.minX + rx - k * rx, y: rect.minY), transform: transform)
        closeSubpath()
    }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat,
                       clockwise: Bool, transform: CGAffineTransform = .identity) {
        // CG's `clockwise` is in a y-up space: clockwise means decreasing angle.
        var sweep = endAngle - startAngle
        if clockwise { if sweep > 0 { sweep -= 2 * .pi } } else if sweep < 0 { sweep += 2 * .pi }
        let segments = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let step = sweep / CGFloat(segments)
        let start = CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))
        if elements.isEmpty { move(to: start, transform: transform) } else { addLine(to: start, transform: transform) }
        let k = 4 / 3 * tan(step / 4)
        var angle = startAngle
        for _ in 0..<segments {
            let next = angle + step
            let p0 = CGPoint(x: cos(angle), y: sin(angle)), p3 = CGPoint(x: cos(next), y: sin(next))
            let c1 = CGPoint(x: center.x + radius * (p0.x - k * p0.y), y: center.y + radius * (p0.y + k * p0.x))
            let c2 = CGPoint(x: center.x + radius * (p3.x + k * p3.y), y: center.y + radius * (p3.y - k * p3.x))
            addCurve(to: CGPoint(x: center.x + radius * p3.x, y: center.y + radius * p3.y),
                     control1: c1, control2: c2, transform: transform)
            angle = next
        }
    }

    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) {
        for element in path.elements {
            switch element {
            case .move(let p): elements.append(.move(p.applying(transform)))
            case .line(let p): elements.append(.line(p.applying(transform)))
            case .quad(let c, let p): elements.append(.quad(c.applying(transform), p.applying(transform)))
            case .cubic(let c1, let c2, let p):
                elements.append(.cubic(c1.applying(transform), c2.applying(transform), p.applying(transform)))
            case .close: elements.append(.close)
            }
        }
    }
}
