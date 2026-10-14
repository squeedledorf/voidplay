// Linux stand-in for the slice of Core Animation the skin views use: a layer tree drawn
// through Core Graphics each frame, with basic animations evaluated at draw time.
@_exported import Foundation
@_exported import CoreGraphics

public func CACurrentMediaTime() -> CFTimeInterval { ProcessInfo.processInfo.systemUptime }
public typealias CFTimeInterval = Double

public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0, m14: CGFloat = 0
    public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0, m24: CGFloat = 0
    public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1, m34: CGFloat = 0
    public var m41: CGFloat = 0, m42: CGFloat = 0, m43: CGFloat = 0, m44: CGFloat = 1
    public init() {}

    /// The 2D part, as Core Graphics applies it.
    public var affine: CGAffineTransform { CGAffineTransform(a: m11, b: m12, c: m21, d: m22, tx: m41, ty: m42) }
}

public let CATransform3DIdentity = CATransform3D()

public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m11 = sx; t.m22 = sy; t.m33 = sz; return t
}

public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    var t = CATransform3D(); t.m41 = tx; t.m42 = ty; t.m43 = tz; return t
}

public func CATransform3DMakeAffineTransform(_ m: CGAffineTransform) -> CATransform3D {
    var t = CATransform3D(); t.m11 = m.a; t.m12 = m.b; t.m21 = m.c; t.m22 = m.d; t.m41 = m.tx; t.m42 = m.ty; return t
}

public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool { t == CATransform3DIdentity }

public enum CATransaction {
    public static func begin() {}
    public static func commit() {}
    public static func flush() {}
    public static func setDisableActions(_ flag: Bool) {}
    public static func setAnimationDuration(_ duration: CFTimeInterval) {}
    public static func setCompletionBlock(_ block: (() -> Void)?) { block.map { DispatchQueue.main.async(execute: $0) } }
}

public struct CAMediaTimingFunctionName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
    public static let easeIn = CAMediaTimingFunctionName(rawValue: "easeIn")
    public static let easeOut = CAMediaTimingFunctionName(rawValue: "easeOut")
    public static let easeInEaseOut = CAMediaTimingFunctionName(rawValue: "easeInEaseOut")
    public static let `default` = CAMediaTimingFunctionName(rawValue: "default")
}

open class CAMediaTimingFunction {
    public let name: CAMediaTimingFunctionName
    public init(name: CAMediaTimingFunctionName) { self.name = name }

    func apply(_ t: Double) -> Double {
        switch name {
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInEaseOut, .default: return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        default: return t
        }
    }
}

open class CAAnimation: NSObject {
    open var duration: CFTimeInterval = 0.25
    open var repeatCount: Float = 0
    open var autoreverses = false
    open var beginTime: CFTimeInterval = 0
    open var timingFunction: CAMediaTimingFunction?
    open var isRemovedOnCompletion = true
    open var fillMode: String = "removed"
    open weak var delegate: AnyObject?
    public override init() { super.init() }
}

open class CAPropertyAnimation: CAAnimation {
    open var keyPath: String?
    public init(keyPath: String?) { self.keyPath = keyPath; super.init() }
    public override init() { super.init() }
}

open class CABasicAnimation: CAPropertyAnimation {
    open var fromValue: Any?
    open var toValue: Any?
    open var byValue: Any?
}

/// A rectangle of content in a tree, positioned by `position`/`anchorPoint`, painted from
/// `contents` (a CGImage) or `draw(in:)`.
open class CALayer: NSObject {
    /// Called when any layer changes how it draws; AppKit points it at "redraw the windows".
    nonisolated(unsafe) public static var didChange: (() -> Void)?

    open var bounds: CGRect = .zero {
        didSet { if bounds.size != oldValue.size { setNeedsLayout() }; if bounds != oldValue { Self.didChange?() } }
    }
    open var position: CGPoint = .zero { didSet { if position != oldValue { Self.didChange?() } } }
    open var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    open var zPosition: CGFloat = 0
    open var transform = CATransform3DIdentity { didSet { Self.didChange?() } }
    open var contents: Any? { didSet { Self.didChange?() } }
    open var contentsScale: CGFloat = 1
    open var contentsGravity: CALayerContentsGravity = .resize
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var masksToBounds = false
    open var isHidden = false { didSet { if isHidden != oldValue { Self.didChange?() } } }
    open var opacity: Float = 1 { didSet { Self.didChange?() } }
    open var backgroundColor: CGColor? { didSet { Self.didChange?() } }
    open var borderColor: CGColor?
    open var borderWidth: CGFloat = 0
    open var cornerRadius: CGFloat = 0
    open var isOpaque = false
    open var isGeometryFlipped = false
    open var needsDisplayOnBoundsChange = false
    open var actions: [String: Any]?
    open var name: String?
    open weak var delegate: AnyObject?
    open var magnificationFilter: CALayerContentsFilter = .linear
    open var minificationFilter: CALayerContentsFilter = .linear
    open var shadowOpacity: Float = 0
    open var shadowRadius: CGFloat = 0
    open var shadowOffset: CGSize = .zero
    open var shadowColor: CGColor?
    open var mask: CALayer?
    open var speed: Float = 1
    open var timeOffset: CFTimeInterval = 0
    open var beginTime: CFTimeInterval = 0
    public private(set) var sublayers: [CALayer]?
    public private(set) weak var superlayer: CALayer?
    private var animations: [String: (CAAnimation, CFTimeInterval)] = [:]
    private var needsLayoutFlag = false

    public override init() { super.init() }
    public init(layer: Any) { super.init() }
    public required init?(coder: NSCoder) { super.init() }

    open var frame: CGRect {
        get {
            CGRect(x: position.x - anchorPoint.x * bounds.width, y: position.y - anchorPoint.y * bounds.height,
                   width: bounds.width, height: bounds.height)
        }
        set {
            bounds.size = newValue.size
            position = CGPoint(x: newValue.minX + anchorPoint.x * newValue.width,
                               y: newValue.minY + anchorPoint.y * newValue.height)
        }
    }

    // MARK: Tree

    open func addSublayer(_ layer: CALayer) {
        layer.removeFromSuperlayer()
        sublayers = (sublayers ?? []) + [layer]
        layer.superlayer = self
        Self.didChange?()
    }

    open func insertSublayer(_ layer: CALayer, at index: UInt32) {
        layer.removeFromSuperlayer()
        var list = sublayers ?? []
        list.insert(layer, at: min(Int(index), list.count))
        sublayers = list
        layer.superlayer = self
    }

    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        let index = sibling.flatMap { s in sublayers?.firstIndex { $0 === s } } ?? 0
        insertSublayer(layer, at: UInt32(index))
    }

    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        let index = sibling.flatMap { s in sublayers?.firstIndex { $0 === s } }.map { $0 + 1 } ?? (sublayers?.count ?? 0)
        insertSublayer(layer, at: UInt32(index))
    }

    open func removeFromSuperlayer() {
        superlayer?.sublayers?.removeAll { $0 === self }
        superlayer = nil
        Self.didChange?()
    }

    // MARK: Display and layout

    open func setNeedsDisplay() {}
    open func setNeedsDisplay(_ rect: CGRect) {}
    open func displayIfNeeded() {}
    open func display() {}
    open func draw(in ctx: CGContext) {}
    open func setNeedsLayout() { needsLayoutFlag = true }
    open func layoutIfNeeded() { if needsLayoutFlag { needsLayoutFlag = false; layoutSublayers() } }
    open func layoutSublayers() {}
    open func action(forKey event: String) -> Any? { nil }
    open func removeAllAnimations() { animations.removeAll() }

    // MARK: Animation (evaluated when drawn)

    open func add(_ animation: CAAnimation, forKey key: String?) {
        let start = animation.beginTime > 0 ? animation.beginTime : convertTime(CACurrentMediaTime(), from: nil)
        animations[key ?? UUID().uuidString] = (animation, start)
        Self.didChange?()
    }

    open func removeAnimation(forKey key: String) { animations[key] = nil }
    open func animation(forKey key: String) -> CAAnimation? { animations[key]?.0 }
    open var animationKeys: [String]? { animations.isEmpty ? nil : Array(animations.keys) }

    /// This layer's local time for a host time (speed, timeOffset and beginTime as Core Animation).
    open func convertTime(_ t: CFTimeInterval, from layer: CALayer?) -> CFTimeInterval {
        (t - beginTime) * Double(speed) + timeOffset
    }

    public var hasRunningAnimations: Bool {
        (speed != 0 && !animations.isEmpty) || (sublayers ?? []).contains { $0.hasRunningAnimations }
    }

    /// Position with any running position animation applied.
    private func presentationPosition(at now: CFTimeInterval) -> CGPoint {
        var p = position
        let local = convertTime(now, from: nil)
        for (animation, start) in animations.values {
            guard let basic = animation as? CABasicAnimation, let keyPath = basic.keyPath, basic.duration > 0 else { continue }
            var progress = (local - start) / basic.duration
            if basic.repeatCount == .infinity { progress = progress.truncatingRemainder(dividingBy: 1); if progress < 0 { progress += 1 } }
            else { progress = min(max(progress, 0), 1) }
            progress = basic.timingFunction?.apply(progress) ?? progress
            func number(_ v: Any?) -> CGFloat? { (v as? CGFloat) ?? (v as? Double).map { CGFloat($0) } ?? (v as? Int).map { CGFloat($0) }
                ?? (v as? NSNumber).map { CGFloat($0.doubleValue) } }
            switch keyPath {
            case "position.x":
                if let from = number(basic.fromValue), let to = number(basic.toValue) { p.x = from + (to - from) * progress }
            case "position.y":
                if let from = number(basic.fromValue), let to = number(basic.toValue) { p.y = from + (to - from) * progress }
            case "position":
                if let from = basic.fromValue as? CGPoint, let to = basic.toValue as? CGPoint {
                    p = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
                }
            default: break
            }
        }
        return p
    }

    /// Paints this layer and its sublayers into `ctx`, which is in the superlayer's space.
    public func render(in ctx: CGContext, at now: CFTimeInterval = CACurrentMediaTime()) {
        guard !isHidden, opacity > 0 else { return }
        layoutIfNeeded()
        ctx.saveGState()
        let p = presentationPosition(at: now)
        ctx.translateBy(x: p.x, y: p.y)
        if !CATransform3DIsIdentity(transform) { ctx.concatenate(transform.affine) }
        ctx.translateBy(x: -anchorPoint.x * bounds.width - bounds.minX, y: -anchorPoint.y * bounds.height - bounds.minY)
        if masksToBounds { ctx.clip(to: bounds) }
        if opacity < 1 { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
        if let backgroundColor { ctx.setFillColor(backgroundColor); ctx.fill(bounds) }
        if let image = contents.flatMap({ $0 as? CGImage }) {
            ctx.saveGState()
            ctx.interpolationQuality = magnificationFilter == .nearest ? .none : .default
            var frame = contentsFrame(for: image)
            // A bitmap rendered for this layer's size (rounded up to whole pixels) is blitted 1:1 at
            // a whole-pixel origin, as Core Animation does, not resampled into a fractional box:
            // resampling smeared the classic marquee's 6px glyphs at the 1.25 skin scale.
            let natural = CGSize(width: CGFloat(image.width) / contentsScale, height: CGFloat(image.height) / contentsScale)
            if abs(natural.width - frame.width) <= 1, abs(natural.height - frame.height) <= 1 {
                let corner = CGPoint(x: frame.minX, y: frame.maxY).applying(ctx.ctm)
                let snapped = CGPoint(x: corner.x.rounded(), y: corner.y.rounded()).applying(ctx.ctm.inverted())
                frame = CGRect(x: snapped.x, y: snapped.y - natural.height, width: natural.width, height: natural.height)
                ctx.interpolationQuality = .none
            }
            ctx.draw(image, in: frame)
            ctx.restoreGState()
        }
        draw(in: ctx)
        for layer in sublayers ?? [] { layer.render(in: ctx, at: now) }
        if opacity < 1 { ctx.setAlpha(CGFloat(opacity)); ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    private func contentsFrame(for image: CGImage) -> CGRect {
        let size = CGSize(width: CGFloat(image.width) / contentsScale, height: CGFloat(image.height) / contentsScale)
        switch contentsGravity {
        case .topLeft: return CGRect(x: bounds.minX, y: bounds.maxY - size.height, width: size.width, height: size.height)
        case .left: return CGRect(x: bounds.minX, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        case .center: return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                    width: size.width, height: size.height)
        default: return bounds
        }
    }
}

public struct CALayerContentsGravity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let resize = CALayerContentsGravity(rawValue: "resize")
    public static let resizeAspect = CALayerContentsGravity(rawValue: "resizeAspect")
    public static let resizeAspectFill = CALayerContentsGravity(rawValue: "resizeAspectFill")
    public static let center = CALayerContentsGravity(rawValue: "center")
    public static let topLeft = CALayerContentsGravity(rawValue: "topLeft")
    public static let left = CALayerContentsGravity(rawValue: "left")
}

public struct CALayerContentsFilter: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = CALayerContentsFilter(rawValue: "linear")
    public static let nearest = CALayerContentsFilter(rawValue: "nearest")
    public static let trilinear = CALayerContentsFilter(rawValue: "trilinear")
}
