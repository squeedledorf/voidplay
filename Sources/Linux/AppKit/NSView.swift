import Foundation
import CoreGraphics
import QuartzCore

/// A rectangle of a window that draws through Core Graphics and receives events. The hosting
/// NSWindow composites the view tree into one GTK drawing area.
open class NSView: NSResponder {
    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let none = AutoresizingMask([])
        public static let minXMargin = AutoresizingMask(rawValue: 1)
        public static let width = AutoresizingMask(rawValue: 2)
        public static let maxXMargin = AutoresizingMask(rawValue: 4)
        public static let minYMargin = AutoresizingMask(rawValue: 8)
        public static let height = AutoresizingMask(rawValue: 16)
        public static let maxYMargin = AutoresizingMask(rawValue: 32)
    }

    open var frame: NSRect {
        didSet {
            guard frame != oldValue else { return }
            if frame.size != oldValue.size {
                let oldSize = oldValue.size
                bounds.size = frame.size
                resizeSubviews(withOldSize: oldSize)
                needsLayout = true
            }
            superview?.needsDisplay = true
            needsDisplay = true
        }
    }

    open var bounds: NSRect

    public private(set) var subviews: [NSView] = []
    public private(set) weak var superview: NSView?
    public internal(set) weak var window: NSWindow? {
        didSet { if window !== oldValue { subviews.forEach { $0.window = window }; viewDidMoveToWindow() } }
    }

    open var isFlipped: Bool { false }

    /// Whether this view's y axis runs opposite to its superview's (the window base is y-up). A
    /// non-flipped view inside a flipped one needs the flip as much as a flipped view in a normal one.
    private var flipsAgainstSuperview: Bool { isFlipped != (superview?.isFlipped ?? false) }
    open var isOpaque: Bool { false }
    open var isHidden = false { didSet { superview?.needsDisplay = true } }
    open var alphaValue: CGFloat = 1 { didSet { needsDisplay = true } }
    open var autoresizingMask: AutoresizingMask = []
    open var autoresizesSubviews = true
    open var wantsLayer = false {
        didSet { if wantsLayer, layer == nil { layer = makeBackingLayer() } }
    }
    /// Backing layer; its sublayers are composited above this view's own drawing.
    open var layer: CALayer? {
        didSet { layer?.bounds = bounds }
    }
    open func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.bounds = bounds
        layer.anchorPoint = .zero
        return layer
    }
    public enum LayerContentsRedrawPolicy: Int, Sendable { case never, onSetNeedsDisplay, duringViewResize, beforeViewResize, crossfade }
    open var layerContentsRedrawPolicy: LayerContentsRedrawPolicy = .duringViewResize
    open var canDrawSubviewsIntoLayer = false
    open var toolTip: String?
    open var identifier: NSUserInterfaceItemIdentifier?
    open var tag: Int { -1 }
    open var needsLayout = false
    open var translatesAutoresizingMaskIntoConstraints = true
    open var postsFrameChangedNotifications = false
    public private(set) var trackingAreas: [NSTrackingArea] = []
    public private(set) var registeredDraggedTypes: [NSPasteboard.PasteboardType] = []

    open var needsDisplay = false {
        didSet { if needsDisplay { window?.viewNeedsDisplay() } }
    }

    open var visibleRect: NSRect { bounds }
    open var intrinsicContentSize: NSSize { NSSize(width: -1, height: -1) }

    public init(frame frameRect: NSRect) {
        frame = frameRect
        bounds = NSRect(origin: .zero, size: frameRect.size)
        super.init()
    }

    public convenience override init() { self.init(frame: .zero) }

    public required init?(coder: NSCoder) { nil }

    // MARK: Hierarchy

    open func addSubview(_ view: NSView) {
        view.removeFromSuperview()
        subviews.append(view)
        view.superview = self
        view.nextResponder = self
        view.window = window
        needsDisplay = true
    }

    open func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo other: NSView?) {
        addSubview(view)
        guard let other, let otherIndex = subviews.firstIndex(where: { $0 === other }) else { return }
        subviews.removeLast()
        subviews.insert(view, at: place == .below ? otherIndex : otherIndex + 1)
    }

    open func removeFromSuperview() {
        guard let parent = superview else { return }
        parent.subviews.removeAll { $0 === self }
        parent.needsDisplay = true
        superview = nil
        window = nil
    }

    open func viewDidMoveToWindow() {}
    open func viewWillMove(toWindow newWindow: NSWindow?) {}
    open func viewDidMoveToSuperview() {}

    open func isDescendant(of view: NSView) -> Bool {
        var current: NSView? = self
        while let v = current {
            if v === view { return true }
            current = v.superview
        }
        return false
    }

    // MARK: Layout

    open func layout() { subviews.forEach { $0.layoutSubtreeIfNeeded() } }

    open func layoutSubtreeIfNeeded() {
        if needsLayout { needsLayout = false; layout() } else { subviews.forEach { $0.layoutSubtreeIfNeeded() } }
    }

    open func setFrameOrigin(_ origin: NSPoint) { frame.origin = origin }
    open func setFrameSize(_ size: NSSize) { frame.size = size }
    open func setBoundsSize(_ size: NSSize) { bounds.size = size; needsDisplay = true }
    open func setBoundsOrigin(_ origin: NSPoint) { bounds.origin = origin; needsDisplay = true }

    /// Springs and struts, as AppKit resizes subviews by their autoresizing masks.
    open func resizeSubviews(withOldSize oldSize: NSSize) {
        guard autoresizesSubviews else { return }
        let dw = bounds.width - oldSize.width, dh = bounds.height - oldSize.height
        for view in subviews where !view.autoresizingMask.isEmpty {
            view.resize(withOldSuperviewSize: oldSize, dw: dw, dh: dh)
        }
    }

    private func resize(withOldSuperviewSize oldSize: NSSize, dw: CGFloat, dh: CGFloat) {
        var f = frame
        let m = autoresizingMask
        func share(_ flexible: [Bool], _ delta: CGFloat) -> [CGFloat] {
            let n = flexible.filter { $0 }.count
            return flexible.map { $0 && n > 0 ? delta / CGFloat(n) : 0 }
        }
        let x = share([m.contains(.minXMargin), m.contains(.width), m.contains(.maxXMargin)], dw)
        let y = share([m.contains(.minYMargin), m.contains(.height), m.contains(.maxYMargin)], dh)
        f.origin.x += x[0]; f.size.width += x[1]
        f.origin.y += y[0]; f.size.height += y[1]
        frame = f
    }

    // MARK: Drawing

    open func draw(_ dirtyRect: NSRect) {}

    open func setNeedsDisplay(_ invalidRect: NSRect) { needsDisplay = true }

    /// Draws now as far as GTK allows: the next frame repaints this window.
    open func display() { needsDisplay = true }
    open func displayIfNeeded() {}
    open func display(_ rect: NSRect) { needsDisplay = true }

    /// Paints this view and its subviews into `ctx`, which is in the superview's coordinates.
    func drawTree(in ctx: CGContext, dirty: NSRect) {
        guard !isHidden, alphaValue > 0 else { return }
        ctx.saveGState()
        ctx.translateBy(x: frame.origin.x, y: frame.origin.y)
        if flipsAgainstSuperview {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        ctx.clip(to: bounds)
        if alphaValue < 1 { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: isFlipped)
        if let background = layer?.backgroundColor {
            ctx.saveGState(); ctx.setFillColor(background); ctx.fill(bounds); ctx.restoreGState()
        }
        draw(bounds)
        NSGraphicsContext.current = previous
        needsDisplay = false
        if let layer {
            layer.bounds = bounds
            for sublayer in layer.sublayers ?? [] { sublayer.render(in: ctx) }
            if layer.hasRunningAnimations { window?.viewNeedsDisplay() }
        }
        for view in subviews { view.drawTree(in: ctx, dirty: dirty) }
        if alphaValue < 1 { ctx.setAlpha(alphaValue); ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    // MARK: Coordinates

    /// This view's bounds → its window's base coordinates (bottom-left origin).
    private func transformToWindow() -> CGAffineTransform {
        var t = CGAffineTransform(translationX: -bounds.origin.x, y: -bounds.origin.y)
        if flipsAgainstSuperview { t = t.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)) }
        t = t.concatenating(CGAffineTransform(translationX: frame.origin.x, y: frame.origin.y))
        if let superview { t = t.concatenating(superview.transformToWindow()) }
        return t
    }

    open func convert(_ point: NSPoint, from view: NSView?) -> NSPoint {
        let inWindow = view.map { point.applying($0.transformToWindow()) } ?? point
        return inWindow.applying(transformToWindow().inverted())
    }

    open func convert(_ point: NSPoint, to view: NSView?) -> NSPoint {
        let inWindow = point.applying(transformToWindow())
        return view.map { inWindow.applying($0.transformToWindow().inverted()) } ?? inWindow
    }

    open func convert(_ rect: NSRect, from view: NSView?) -> NSRect {
        let inWindow = view.map { rect.applying($0.transformToWindow()) } ?? rect
        return inWindow.applying(transformToWindow().inverted())
    }

    open func convert(_ rect: NSRect, to view: NSView?) -> NSRect {
        let inWindow = rect.applying(transformToWindow())
        return view.map { inWindow.applying($0.transformToWindow().inverted()) } ?? inWindow
    }

    open func convert(_ size: NSSize, from view: NSView?) -> NSSize { size }
    open func convert(_ size: NSSize, to view: NSView?) -> NSSize { size }
    open func convertToBacking(_ rect: NSRect) -> NSRect {
        let s = window?.backingScaleFactor ?? 1
        return NSRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
    }
    open func convertFromBacking(_ rect: NSRect) -> NSRect {
        let s = window?.backingScaleFactor ?? 1
        return NSRect(x: rect.minX / s, y: rect.minY / s, width: rect.width / s, height: rect.height / s)
    }

    /// Deepest visible view under `point` (in the superview's coordinates).
    open func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        for view in subviews.reversed() {
            if let hit = view.hitTest(local) { return hit }
        }
        return self
    }

    open func mouse(_ point: NSPoint, in rect: NSRect) -> Bool { rect.contains(point) }

    // MARK: Events and tracking

    open func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    open func menu(for event: NSEvent) -> NSMenu? { menu }
    open var menu: NSMenu?
    open var focusRingType: NSFocusRingType = .default

    /// As AppKit: a right click shows the view's context menu, else travels up the responder chain.
    open override func rightMouseDown(with event: NSEvent) {
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    open func addTrackingArea(_ area: NSTrackingArea) { trackingAreas.append(area) }
    open func removeTrackingArea(_ area: NSTrackingArea) { trackingAreas.removeAll { $0 === area } }
    open func updateTrackingAreas() {}
    open func addCursorRect(_ rect: NSRect, cursor: NSCursor) {}
    open func resetCursorRects() {}
    open func discardCursorRects() {}

    open func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) { registeredDraggedTypes = newTypes }
    open func unregisterDraggedTypes() { registeredDraggedTypes = [] }

    open func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { [] }
    open func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    open func draggingExited(_ sender: NSDraggingInfo?) {}
    open func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    open func performDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
    open func concludeDragOperation(_ sender: NSDraggingInfo?) {}

    // MARK: Accessibility (no AT-SPI bridge yet)

    open func accessibilityChildren() -> [Any]? { nil }
    open func setAccessibilityLabel(_ label: String?) {}
    open func setAccessibilityIdentifier(_ identifier: String?) {}
    open func setAccessibilityRole(_ role: NSAccessibility.Role?) {}
    open func setAccessibilityElement(_ isElement: Bool) {}
    open func setAccessibilityHelp(_ help: String?) {}
    open func setAccessibilityChildren(_ children: [Any]?) {}
    open func isAccessibilityElement() -> Bool { false }
}

public struct NSUserInterfaceItemIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum NSAccessibility {
    public struct Role: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let button = Role(rawValue: "AXButton")
        public static let slider = Role(rawValue: "AXSlider")
        public static let group = Role(rawValue: "AXGroup")
        public static let staticText = Role(rawValue: "AXStaticText")
        public static let list = Role(rawValue: "AXList")
        public static let row = Role(rawValue: "AXRow")
    }
}
