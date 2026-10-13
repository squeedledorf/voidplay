import Foundation
import CoreGraphics
import CGtk

public protocol NSWindowDelegate: AnyObject {
    func windowShouldClose(_ sender: NSWindow) -> Bool
    func windowWillClose(_ notification: Notification)
    func windowDidMove(_ notification: Notification)
    func windowDidResize(_ notification: Notification)
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize
    func windowDidBecomeKey(_ notification: Notification)
    func windowDidResignKey(_ notification: Notification)
    func windowDidBecomeMain(_ notification: Notification)
    func windowDidResignMain(_ notification: Notification)
    func windowDidMiniaturize(_ notification: Notification)
    func windowDidDeminiaturize(_ notification: Notification)
    func windowWillMiniaturize(_ notification: Notification)
    func windowDidChangeOcclusionState(_ notification: Notification)
    func windowDidChangeBackingProperties(_ notification: Notification)
    func windowDidChangeScreen(_ notification: Notification)
    func windowDidEndLiveResize(_ notification: Notification)
    func windowWillStartLiveResize(_ notification: Notification)
}

extension NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    public func windowWillClose(_ notification: Notification) {}
    public func windowDidMove(_ notification: Notification) {}
    public func windowDidResize(_ notification: Notification) {}
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize { frameSize }
    public func windowDidBecomeKey(_ notification: Notification) {}
    public func windowDidResignKey(_ notification: Notification) {}
    public func windowDidBecomeMain(_ notification: Notification) {}
    public func windowDidResignMain(_ notification: Notification) {}
    public func windowDidMiniaturize(_ notification: Notification) {}
    public func windowDidDeminiaturize(_ notification: Notification) {}
    public func windowWillMiniaturize(_ notification: Notification) {}
    public func windowDidChangeOcclusionState(_ notification: Notification) {}
    public func windowDidChangeBackingProperties(_ notification: Notification) {}
    public func windowDidChangeScreen(_ notification: Notification) {}
    public func windowDidEndLiveResize(_ notification: Notification) {}
    public func windowWillStartLiveResize(_ notification: Notification) {}
}

/// A top-level window: a GtkWindow holding one drawing area that composites the NSView tree.
/// `frame` is in AppKit screen coordinates (bottom-left origin); placement goes through
/// `WindowPlacement` because Wayland clients cannot move their own windows.
open class NSWindow: NSResponder {
    public struct StyleMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let borderless = StyleMask([])
        public static let titled = StyleMask(rawValue: 1 << 0)
        public static let closable = StyleMask(rawValue: 1 << 1)
        public static let miniaturizable = StyleMask(rawValue: 1 << 2)
        public static let resizable = StyleMask(rawValue: 1 << 3)
        public static let utilityWindow = StyleMask(rawValue: 1 << 4)
        public static let fullSizeContentView = StyleMask(rawValue: 1 << 15)
        public static let nonactivatingPanel = StyleMask(rawValue: 1 << 7)
    }

    public enum BackingStoreType: UInt, Sendable { case retained, nonretained, buffered }
    public enum OrderingMode: Int, Sendable { case below = -1, out = 0, above = 1 }
    public enum TitleVisibility: Int, Sendable { case visible, hidden }

    public struct Level: RawRepresentable, Hashable, Comparable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public init(_ rawValue: Int) { self.rawValue = rawValue }
        public static let normal = Level(0)
        public static let floating = Level(3)
        public static let modalPanel = Level(8)
        public static let mainMenu = Level(24)
        public static let statusBar = Level(25)
        public static let popUpMenu = Level(101)
        public static let screenSaver = Level(1000)
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct OcclusionState: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let visible = OcclusionState(rawValue: 1 << 1)
    }

    public struct CollectionBehavior: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let canJoinAllSpaces = CollectionBehavior(rawValue: 1)
        public static let moveToActiveSpace = CollectionBehavior(rawValue: 2)
        public static let managed = CollectionBehavior(rawValue: 4)
        public static let transient = CollectionBehavior(rawValue: 8)
        public static let stationary = CollectionBehavior(rawValue: 16)
        public static let participatesInCycle = CollectionBehavior(rawValue: 32)
        public static let ignoresCycle = CollectionBehavior(rawValue: 64)
        public static let fullScreenAuxiliary = CollectionBehavior(rawValue: 256)
        public static let fullScreenNone = CollectionBehavior(rawValue: 512)
    }

    public static let didMoveNotification = Notification.Name("NSWindowDidMoveNotification")
    public static let didResizeNotification = Notification.Name("NSWindowDidResizeNotification")
    public static let willCloseNotification = Notification.Name("NSWindowWillCloseNotification")
    public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
    public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
    public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")
    public static let didResignMainNotification = Notification.Name("NSWindowDidResignMainNotification")
    public static let didMiniaturizeNotification = Notification.Name("NSWindowDidMiniaturizeNotification")
    public static let didDeminiaturizeNotification = Notification.Name("NSWindowDidDeminiaturizeNotification")
    public static let didChangeOcclusionStateNotification = Notification.Name("NSWindowDidChangeOcclusionStateNotification")
    public static let didChangeBackingPropertiesNotification = Notification.Name("NSWindowDidChangeBackingPropertiesNotification")
    public static let didChangeScreenNotification = Notification.Name("NSWindowDidChangeScreenNotification")

    // MARK: GTK objects

    let gtkWindow: UnsafeMutablePointer<GtkWidget>
    let canvas: UnsafeMutablePointer<GtkWidget>
    /// The compositor's handle for this window, once placement has found it.
    var placementID: String?
    /// Unique title the placement backend matches before the real title is applied.
    let placementToken: String

    // MARK: State

    public private(set) var frame: NSRect
    open weak var delegate: NSWindowDelegate?
    open var styleMask: StyleMask
    open var level: Level = .normal
    open var collectionBehavior: CollectionBehavior = []
    open var isOpaque = true { didSet { applyBackground() } }
    open var backgroundColor: NSColor = .black { didSet { applyBackground() } }
    open var hasShadow = true
    open var isMovableByWindowBackground = false
    open var isMovable = true
    open var ignoresMouseEvents = false
    open var acceptsMouseMovedEvents = false
    open var isReleasedWhenClosed = false
    open var hidesOnDeactivate = false
    open var alphaValue: CGFloat = 1 { didSet { gtk_widget_set_opacity(gtkWindow, Double(alphaValue)) } }
    open var minSize = NSSize(width: 1, height: 1)
    open var maxSize = NSSize(width: 100_000, height: 100_000)
    open var contentMinSize = NSSize(width: 1, height: 1)
    open var contentMaxSize = NSSize(width: 100_000, height: 100_000)
    open var titleVisibility: TitleVisibility = .visible
    open var titlebarAppearsTransparent = false
    open var identifier: NSUserInterfaceItemIdentifier?
    open var tabbingMode: Int = 0
    open var animationBehavior: Int = 0
    open var windowController: NSWindowController?
    public private(set) var isVisible = false
    public private(set) var isMiniaturized = false
    public private(set) weak var firstResponder: NSResponder?
    public private(set) var childWindows: [NSWindow]? = []
    public private(set) weak var parent: NSWindow?

    open var title: String = "" {
        didSet { if placementID != nil { gtk_window_set_title(gtkWindowPtr, title) } }
    }

    open var contentView: NSView? {
        didSet {
            oldValue?.window = nil
            guard let view = contentView else { return }
            view.frame = NSRect(origin: .zero, size: frame.size)
            view.nextResponder = self
            view.window = self
            viewNeedsDisplay()
        }
    }

    public var windowNumber: Int { Int(bitPattern: UInt(bitPattern: ObjectIdentifier(self).hashValue)) & 0x7FFF_FFFF }
    open var isKeyWindow: Bool { gtk_window_is_active(gtkWindowPtr) != 0 }
    open var isMainWindow: Bool { isKeyWindow }
    open var canBecomeKey: Bool { true }
    open var canBecomeMain: Bool { true }
    open var backingScaleFactor: CGFloat { CGFloat(gtk_widget_get_scale_factor(canvas)) }
    open var occlusionState: OcclusionState { isVisible && !isMiniaturized ? .visible : [] }
    open var screen: NSScreen? { NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main }
    open var contentLayoutRect: NSRect { NSRect(origin: .zero, size: frame.size) }

    var gtkWindowPtr: UnsafeMutablePointer<GtkWindow> { cgtk_window(gtkWindow) }

    private static var nextToken = 0
    static var all: [NSWindow] = []

    // MARK: Creation

    public init(contentRect: NSRect, styleMask style: StyleMask, backing: BackingStoreType, defer flag: Bool) {
        frame = contentRect
        styleMask = style
        Self.nextToken += 1
        placementToken = "voidplay-window-\(getpid())-\(Self.nextToken)"
        gtkWindow = gtk_window_new()
        canvas = gtk_drawing_area_new()
        super.init()
        let window = gtkWindowPtr
        gtk_window_set_title(window, placementToken)
        gtk_window_set_decorated(window, style.contains(.titled) ? 1 : 0)
        gtk_window_set_resizable(window, style.contains(.resizable) ? 1 : 0)
        gtk_window_set_default_size(window, Int32(contentRect.width), Int32(contentRect.height))
        gtk_widget_set_size_request(canvas, Int32(contentRect.width), Int32(contentRect.height))
        gtk_window_set_child(window, canvas)
        gtk_window_set_hide_on_close(window, 1)
        installCallbacks()
        applyBackground()
        Self.all.append(self)
    }

    public convenience init(contentRect: NSRect, styleMask style: StyleMask, backing: BackingStoreType,
                            defer flag: Bool, screen: NSScreen?) {
        self.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
    }

    deinit {
        Self.all.removeAll { $0 === self }
    }

    // MARK: Ordering and visibility

    open func makeKeyAndOrderFront(_ sender: Any?) {
        orderFront(sender)
        gtk_window_present(gtkWindowPtr)
    }

    open func orderFront(_ sender: Any?) {
        guard !isVisible else { gtk_window_present(gtkWindowPtr); return }
        isVisible = true
        gtk_window_present(gtkWindowPtr)
        WindowPlacement.shared.windowDidShow(self)
        postOcclusion()
    }

    open func orderFrontRegardless() { orderFront(nil) }
    open func orderBack(_ sender: Any?) { orderFront(sender) }
    open func makeKey() { gtk_window_present(gtkWindowPtr) }
    open func makeMain() { makeKey() }
    open func becomeKey() {}
    open func resignKey() {}

    open func order(_ place: OrderingMode, relativeTo otherWindow: Int) {
        if place == .out { orderOut(nil) } else { orderFront(nil) }
    }

    open func orderOut(_ sender: Any?) {
        guard isVisible else { return }
        isVisible = false
        gtk_widget_set_visible(gtkWindow, 0)
        WindowPlacement.shared.windowDidHide(self)
        postOcclusion()
    }

    open func close() {
        let note = Notification(name: Self.willCloseNotification, object: self)
        delegate?.windowWillClose(note)
        NotificationCenter.default.post(note)
        orderOut(nil)
    }

    open func performClose(_ sender: Any?) {
        if delegate?.windowShouldClose(self) ?? true { close() }
    }

    open func miniaturize(_ sender: Any?) {
        let note = Notification(name: Self.didMiniaturizeNotification, object: self)
        delegate?.windowWillMiniaturize(note)
        gtk_window_minimize(gtkWindowPtr)
        isMiniaturized = true
        delegate?.windowDidMiniaturize(note)
        NotificationCenter.default.post(note)
    }

    open func deminiaturize(_ sender: Any?) {
        gtk_window_unminimize(gtkWindowPtr)
        isMiniaturized = false
        let note = Notification(name: Self.didDeminiaturizeNotification, object: self)
        delegate?.windowDidDeminiaturize(note)
        NotificationCenter.default.post(note)
    }

    open func performMiniaturize(_ sender: Any?) { miniaturize(sender) }

    open func addChildWindow(_ child: NSWindow, ordered place: OrderingMode) {
        child.parent = self
        childWindows?.append(child)
    }

    open func removeChildWindow(_ child: NSWindow) {
        childWindows?.removeAll { $0 === child }
        child.parent = nil
    }

    private func postOcclusion() {
        let note = Notification(name: Self.didChangeOcclusionStateNotification, object: self)
        delegate?.windowDidChangeOcclusionState(note)
        NotificationCenter.default.post(note)
    }

    // MARK: Geometry

    open func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let resized = frameRect.size != frame.size
        let moved = frameRect.origin != frame.origin
        frame = frameRect
        if resized {
            gtk_widget_set_size_request(canvas, Int32(frameRect.width), Int32(frameRect.height))
            gtk_window_set_default_size(gtkWindowPtr, Int32(frameRect.width), Int32(frameRect.height))
            contentView?.frame = NSRect(origin: .zero, size: frameRect.size)
        }
        WindowPlacement.shared.place(self, resized: resized)
        if resized {
            let note = Notification(name: Self.didResizeNotification, object: self)
            delegate?.windowDidResize(note)
            NotificationCenter.default.post(note)
        }
        if moved { postDidMove() }
        if flag { viewNeedsDisplay() }
    }

    open func setFrame(_ frameRect: NSRect, display: Bool, animate: Bool) { setFrame(frameRect, display: display) }

    open func setFrameOrigin(_ point: NSPoint) {
        setFrame(NSRect(origin: point, size: frame.size), display: false)
    }

    open func setFrameTopLeftPoint(_ point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x, y: point.y - frame.height))
    }

    open func setContentSize(_ size: NSSize) {
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    open func center() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
    }

    open func frameRect(forContentRect contentRect: NSRect) -> NSRect { contentRect }
    open func contentRect(forFrameRect frameRect: NSRect) -> NSRect { frameRect }

    open func convertToScreen(_ rect: NSRect) -> NSRect { rect.offsetBy(dx: frame.minX, dy: frame.minY) }
    open func convertFromScreen(_ rect: NSRect) -> NSRect { rect.offsetBy(dx: -frame.minX, dy: -frame.minY) }
    open func convertPoint(toScreen point: NSPoint) -> NSPoint { NSPoint(x: point.x + frame.minX, y: point.y + frame.minY) }
    open func convertPoint(fromScreen point: NSPoint) -> NSPoint { NSPoint(x: point.x - frame.minX, y: point.y - frame.minY) }

    open var mouseLocationOutsideOfEventStream: NSPoint { convertPoint(fromScreen: NSEvent.mouseLocation) }

    /// The compositor moved or resized the window (it reports where it really is).
    func compositorMoved(to origin: NSPoint) {
        guard origin != frame.origin else { return }
        frame.origin = origin
        postDidMove()
    }

    private func postDidMove() {
        let note = Notification(name: Self.didMoveNotification, object: self)
        delegate?.windowDidMove(note)
        NotificationCenter.default.post(note)
    }

    open func invalidateShadow() {}
    open func display() { viewNeedsDisplay() }
    open func displayIfNeeded() {}
    open func update() {}

    open func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let current = firstResponder, current !== responder, !current.resignFirstResponder() { return false }
        firstResponder = responder
        _ = responder?.becomeFirstResponder()
        return true
    }

    func viewNeedsDisplay() { gtk_widget_queue_draw(canvas) }

    private func applyBackground() {
        let cls = "voidplay-transparent"
        if isOpaque { gtk_widget_remove_css_class(gtkWindow, cls) } else { gtk_widget_add_css_class(gtkWindow, cls) }
        NSWindow.installStyles()
        viewNeedsDisplay()
    }

    private static var stylesInstalled = false
    static func installStyles() {
        guard !stylesInstalled, let display = gdk_display_get_default() else { return }
        stylesInstalled = true
        let provider = gtk_css_provider_new()
        gtk_css_provider_load_from_string(provider, "window.voidplay-transparent, window.voidplay-transparent > * { background: transparent; box-shadow: none; }")
        gtk_style_context_add_provider_for_display(display, OpaquePointer(provider), guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
    }

    // MARK: Drawing

    fileprivate func draw(_ cr: OpaquePointer, width: Int32, height: Int32) {
        let ctx = CGContext(_cairo: cr, width: Int(width), height: Int(height))
        // Window base space: origin bottom-left, y up.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        if isOpaque {
            let c = backgroundColor
            ctx.setFillColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
            ctx.fill(NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        contentView.drawTree(in: ctx, dirty: contentView.bounds)
    }

    // MARK: Events

    private var mouseTarget: NSView?
    private var pressedButton = 0
    private var movedSincePress = false
    private var lastLocal = NSPoint.zero

    /// AppKit window coordinates for a GTK canvas point. While the window is being moved under a
    /// held button, the global pointer is used so a move in flight cannot skew the deltas.
    private func location(x: Double, y: Double) -> NSPoint {
        let local = NSPoint(x: x, y: frame.height - y)
        lastLocal = local
        if pressedButton != 0, movedSincePress, let global = WindowPlacement.shared.pointerLocation() {
            return NSPoint(x: global.x - frame.minX, y: global.y - frame.minY)
        }
        return local
    }

    func windowWasMovedByApp() { if pressedButton != 0 { movedSincePress = true } }

    private func dispatch(_ event: NSEvent, _ deliver: (NSResponder) -> Void) {
        guard let event = NSEvent.filter(event) else { return }
        _ = event
        if let target = mouseTarget { deliver(target) }
    }

    fileprivate func pressed(button: Int, count: Int, x: Double, y: Double, state: GdkModifierType) {
        pressedButton = button
        movedSincePress = false
        NSEvent.pressedMouseButtons |= 1 << (button - 1)
        let flags = NSEvent.ModifierFlags(gdk: state)
        NSEvent.modifierFlags = flags
        let point = location(x: x, y: y)
        guard !ignoresMouseEvents, let root = contentView else { return }
        mouseTarget = root.hitTest(point) ?? root
        if let view = mouseTarget, view.acceptsFirstResponder, firstResponder !== view { _ = makeFirstResponder(view) }
        let type: NSEvent.EventType = button == 1 ? .leftMouseDown : button == 3 ? .rightMouseDown : .otherMouseDown
        guard let event = NSEvent.filter(NSEvent(type: type, location: point, modifierFlags: flags, window: self,
                                                 clickCount: count, buttonNumber: button - 1)) else { return }
        switch button {
        case 1: mouseTarget?.mouseDown(with: event)
        case 3: mouseTarget?.rightMouseDown(with: event)
        default: mouseTarget?.otherMouseDown(with: event)
        }
    }

    fileprivate func released(button: Int, x: Double, y: Double, state: GdkModifierType) {
        let flags = NSEvent.ModifierFlags(gdk: state)
        let point = location(x: x, y: y)
        let type: NSEvent.EventType = button == 1 ? .leftMouseUp : button == 3 ? .rightMouseUp : .otherMouseUp
        let target = mouseTarget
        mouseTarget = nil
        pressedButton = 0
        NSEvent.pressedMouseButtons &= ~(1 << (button - 1))
        guard let event = NSEvent.filter(NSEvent(type: type, location: point, modifierFlags: flags, window: self,
                                                 clickCount: 1, buttonNumber: button - 1)) else { return }
        switch button {
        case 1: target?.mouseUp(with: event)
        case 3: target?.rightMouseUp(with: event)
        default: target?.otherMouseUp(with: event)
        }
    }

    fileprivate func motion(x: Double, y: Double, state: GdkModifierType) {
        let flags = NSEvent.ModifierFlags(gdk: state)
        NSEvent.modifierFlags = flags
        let point = location(x: x, y: y)
        NSEvent.lastMouseLocation = convertPoint(toScreen: point)
        if pressedButton != 0, let target = mouseTarget {
            let type: NSEvent.EventType = pressedButton == 1 ? .leftMouseDragged
                : pressedButton == 3 ? .rightMouseDragged : .otherMouseDragged
            guard let event = NSEvent.filter(NSEvent(type: type, location: point, modifierFlags: flags, window: self,
                                                     buttonNumber: pressedButton - 1)) else { return }
            switch pressedButton {
            case 1: target.mouseDragged(with: event)
            case 3: target.rightMouseDragged(with: event)
            default: target.otherMouseDragged(with: event)
            }
            return
        }
        updateTracking(at: point, flags: flags, leaving: false)
    }

    fileprivate func left() { updateTracking(at: lastLocal, flags: NSEvent.modifierFlags, leaving: true) }

    /// Enter/exit/move delivery for every tracking area in the tree.
    private func updateTracking(at point: NSPoint, flags: NSEvent.ModifierFlags, leaving: Bool) {
        guard let root = contentView else { return }
        var stack = [root]
        while let view = stack.popLast() {
            stack += view.subviews
            guard !view.isHidden else { continue }
            let local = view.convert(point, from: nil)
            for area in view.trackingAreas {
                let rect = area.options.contains(.inVisibleRect) ? view.visibleRect : area.rect
                let inside = !leaving && rect.contains(local)
                let owner = area.owner as? NSResponder ?? view
                func event(_ type: NSEvent.EventType) -> NSEvent {
                    NSEvent(type: type, location: point, modifierFlags: flags, window: self, trackingArea: area)
                }
                if inside != area.inside {
                    area.inside = inside
                    if area.options.contains(.mouseEnteredAndExited) {
                        inside ? owner.mouseEntered(with: event(.mouseEntered)) : owner.mouseExited(with: event(.mouseExited))
                    }
                    if inside, area.options.contains(.cursorUpdate) { owner.cursorUpdate(with: event(.mouseMoved)) }
                }
                if inside, area.options.contains(.mouseMoved) { owner.mouseMoved(with: event(.mouseMoved)) }
            }
        }
        if acceptsMouseMovedEvents, !leaving, let first = firstResponder {
            first.mouseMoved(with: NSEvent(type: .mouseMoved, location: point, modifierFlags: flags, window: self))
        }
    }

    fileprivate func scrolled(dx: Double, dy: Double, precise: Bool) -> Bool {
        guard let root = contentView, let target = root.hitTest(lastLocal) else { return false }
        // AppKit: positive deltaY scrolls content down (wheel away from the user); GTK is the reverse.
        let scale: Double = precise ? 1 : 10
        guard let event = NSEvent.filter(NSEvent(type: .scrollWheel, location: lastLocal,
                                                 modifierFlags: NSEvent.modifierFlags, window: self,
                                                 scrollingDeltaX: CGFloat(-dx * scale), scrollingDeltaY: CGFloat(-dy * scale),
                                                 precise: precise)) else { return true }
        target.scrollWheel(with: event)
        return true
    }

    fileprivate func key(down: Bool, keyval: guint, state: GdkModifierType) -> Bool {
        let flags = NSEvent.ModifierFlags(gdk: state)
        NSEvent.modifierFlags = flags
        let unicode = gdk_keyval_to_unicode(gdk_keyval_to_lower(keyval))
        let raw = gdk_keyval_to_unicode(keyval)
        func text(_ u: guint32) -> String? { u == 0 ? nil : Unicode.Scalar(u).map { String(Character($0)) } }
        let event = NSEvent(type: down ? .keyDown : .keyUp, location: lastLocal, modifierFlags: flags, window: self,
                            keyCode: KeyCodes.macKeyCode(for: keyval),
                            characters: text(raw) ?? KeyCodes.functionCharacter(for: keyval),
                            charactersIgnoringModifiers: text(unicode) ?? KeyCodes.functionCharacter(for: keyval))
        guard let filtered = NSEvent.filter(event) else { return true }
        let responder = firstResponder ?? contentView
        if down { responder?.keyDown(with: filtered) } else { responder?.keyUp(with: filtered) }
        return responder != nil
    }

    fileprivate func activeChanged() {
        let key = isKeyWindow
        let note = Notification(name: key ? Self.didBecomeKeyNotification : Self.didResignKeyNotification, object: self)
        if key { delegate?.windowDidBecomeKey(note) } else { delegate?.windowDidResignKey(note) }
        NotificationCenter.default.post(note)
        viewNeedsDisplay()
    }

    fileprivate func closeRequested() -> Bool {
        performClose(nil)
        return true  // the window is hidden by close(), never destroyed by GTK
    }

    // MARK: GTK wiring

    private func installCallbacks() {
        let me = Unmanaged.passUnretained(self).toOpaque()
        gtk_drawing_area_set_draw_func(cgtk_drawing_area(canvas), { _, cr, width, height, data in
            guard let cr, let data else { return }
            Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue().draw(cr, width: width, height: height)
        }, me, nil)

        let click = gtk_gesture_click_new()
        gtk_gesture_single_set_button(click, 0)
        typealias Press = @convention(c) (OpaquePointer?, gint, gdouble, gdouble, gpointer?) -> Void
        let onPress: Press = { gesture, count, x, y, data in
            guard let data else { return }
            let window = Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue()
            window.pressed(button: Int(gtk_gesture_single_get_current_button(gesture)), count: Int(count), x: x, y: y,
                           state: gtk_event_controller_get_current_event_state(gesture))
        }
        let onRelease: Press = { gesture, _, x, y, data in
            guard let data else { return }
            let window = Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue()
            window.released(button: Int(gtk_gesture_single_get_current_button(gesture)), x: x, y: y,
                            state: gtk_event_controller_get_current_event_state(gesture))
        }
        connect(click, "pressed", unsafeBitCast(onPress, to: GCallback.self), me)
        connect(click, "released", unsafeBitCast(onRelease, to: GCallback.self), me)
        gtk_widget_add_controller(canvas, click)

        let motion = gtk_event_controller_motion_new()
        typealias Motion = @convention(c) (OpaquePointer?, gdouble, gdouble, gpointer?) -> Void
        let onMotion: Motion = { controller, x, y, data in
            guard let data else { return }
            Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue()
                .motion(x: x, y: y, state: gtk_event_controller_get_current_event_state(controller))
        }
        typealias Leave = @convention(c) (OpaquePointer?, gpointer?) -> Void
        let onLeave: Leave = { _, data in
            guard let data else { return }
            Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue().left()
        }
        connect(motion, "motion", unsafeBitCast(onMotion, to: GCallback.self), me)
        connect(motion, "enter", unsafeBitCast(onMotion, to: GCallback.self), me)
        connect(motion, "leave", unsafeBitCast(onLeave, to: GCallback.self), me)
        gtk_widget_add_controller(canvas, motion)

        let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
        typealias Scroll = @convention(c) (OpaquePointer?, gdouble, gdouble, gpointer?) -> gboolean
        let onScroll: Scroll = { controller, dx, dy, data in
            guard let data else { return 0 }
            let unit = gtk_event_controller_scroll_get_unit(controller)
            return Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue()
                .scrolled(dx: dx, dy: dy, precise: unit == GDK_SCROLL_UNIT_SURFACE) ? 1 : 0
        }
        connect(scroll, "scroll", unsafeBitCast(onScroll, to: GCallback.self), me)
        gtk_widget_add_controller(canvas, scroll)

        let keys = gtk_event_controller_key_new()
        typealias Key = @convention(c) (OpaquePointer?, guint, guint, GdkModifierType, gpointer?) -> gboolean
        let onKeyDown: Key = { _, keyval, _, state, data in
            guard let data else { return 0 }
            return Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue().key(down: true, keyval: keyval, state: state) ? 1 : 0
        }
        let onKeyUp: Key = { _, keyval, _, state, data in
            guard let data else { return 0 }
            _ = Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue().key(down: false, keyval: keyval, state: state)
            return 0
        }
        connect(keys, "key-pressed", unsafeBitCast(onKeyDown, to: GCallback.self), me)
        connect(keys, "key-released", unsafeBitCast(onKeyUp, to: GCallback.self), me)
        gtk_widget_add_controller(gtkWindow, keys)

        typealias Notify = @convention(c) (OpaquePointer?, OpaquePointer?, gpointer?) -> Void
        let onActive: Notify = { _, _, data in
            guard let data else { return }
            Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue().activeChanged()
        }
        connect(gtkWindow, "notify::is-active", unsafeBitCast(onActive, to: GCallback.self), me)

        typealias Close = @convention(c) (OpaquePointer?, gpointer?) -> gboolean
        let onClose: Close = { _, data in
            guard let data else { return 0 }
            return Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue().closeRequested() ? 1 : 0
        }
        connect(gtkWindow, "close-request", unsafeBitCast(onClose, to: GCallback.self), me)

        typealias Map = @convention(c) (OpaquePointer?, gpointer?) -> Void
        let onMap: Map = { _, data in
            guard let data else { return }
            let window = Unmanaged<NSWindow>.fromOpaque(data).takeUnretainedValue()
            WindowPlacement.shared.windowDidMap(window)
        }
        connect(gtkWindow, "map", unsafeBitCast(onMap, to: GCallback.self), me)
    }

    /// g_signal_connect for GTK objects Swift sees as opaque or typed pointers.
    private func connect<T>(_ object: T, _ signal: String, _ handler: GCallback, _ data: UnsafeMutableRawPointer) {
        let instance = unsafeBitCast(object, to: gpointer.self)
        cgtk_signal_connect(instance, signal, handler, data)
    }
}

open class NSWindowController: NSResponder {
    open var window: NSWindow? {
        didSet { window?.windowController = self }
    }

    public init(window: NSWindow?) {
        self.window = window
        super.init()
        window?.windowController = self
    }

    public required init?(coder: NSCoder) { nil }

    open func showWindow(_ sender: Any?) { window?.makeKeyAndOrderFront(sender) }
    open func close() { window?.close() }
    open func windowDidLoad() {}
    open var isWindowLoaded: Bool { window != nil }
}
