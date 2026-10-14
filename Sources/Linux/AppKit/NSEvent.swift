import Foundation
import CGtk

/// Input event, in AppKit's terms: window coordinates have a bottom-left origin, y up.
open class NSEvent {
    public enum EventType: UInt, Sendable {
        case leftMouseDown = 1, leftMouseUp, rightMouseDown, rightMouseUp, mouseMoved, leftMouseDragged,
             rightMouseDragged, mouseEntered, mouseExited, keyDown, keyUp, flagsChanged
        case scrollWheel = 22, otherMouseDown = 25, otherMouseUp, otherMouseDragged
    }

    public struct ModifierFlags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let capsLock = ModifierFlags(rawValue: 1 << 16)
        public static let shift = ModifierFlags(rawValue: 1 << 17)
        public static let control = ModifierFlags(rawValue: 1 << 18)
        public static let option = ModifierFlags(rawValue: 1 << 19)
        public static let command = ModifierFlags(rawValue: 1 << 20)
        public static let numericPad = ModifierFlags(rawValue: 1 << 21)
        public static let function = ModifierFlags(rawValue: 1 << 23)
        public static let deviceIndependentFlagsMask = ModifierFlags(rawValue: 0xFFFF_0000)

        /// GDK state → AppKit. Ctrl plays Command's role (the shortcut key), Alt plays Option.
        init(gdk state: GdkModifierType) {
            var flags: ModifierFlags = []
            let raw = state.rawValue
            if raw & GDK_SHIFT_MASK.rawValue != 0 { flags.insert(.shift) }
            if raw & GDK_CONTROL_MASK.rawValue != 0 { flags.insert(.command) }
            if raw & GDK_ALT_MASK.rawValue != 0 { flags.insert(.option) }
            if raw & GDK_SUPER_MASK.rawValue != 0 { flags.insert(.control) }
            if raw & GDK_LOCK_MASK.rawValue != 0 { flags.insert(.capsLock) }
            self = flags
        }
    }

    public let type: EventType
    public let locationInWindow: NSPoint
    public let modifierFlags: ModifierFlags
    public let timestamp: TimeInterval
    public weak var window: NSWindow?
    public let clickCount: Int
    public let buttonNumber: Int
    public let keyCode: UInt16
    public let characters: String?
    public let charactersIgnoringModifiers: String?
    public let isARepeat: Bool
    public let scrollingDeltaX: CGFloat
    public let scrollingDeltaY: CGFloat
    public let hasPreciseScrollingDeltas: Bool
    public var deltaX: CGFloat { scrollingDeltaX }
    public var deltaY: CGFloat { scrollingDeltaY }
    public var deltaZ: CGFloat { 0 }
    public let trackingArea: NSTrackingArea?
    public var userData: UnsafeMutableRawPointer? { nil }

    init(type: EventType, location: NSPoint, modifierFlags: ModifierFlags, window: NSWindow?,
         clickCount: Int = 0, buttonNumber: Int = 0, keyCode: UInt16 = 0, characters: String? = nil,
         charactersIgnoringModifiers: String? = nil, isARepeat: Bool = false,
         scrollingDeltaX: CGFloat = 0, scrollingDeltaY: CGFloat = 0, precise: Bool = false,
         trackingArea: NSTrackingArea? = nil) {
        self.type = type
        self.locationInWindow = location
        self.modifierFlags = modifierFlags
        self.timestamp = ProcessInfo.processInfo.systemUptime
        self.window = window
        self.clickCount = clickCount
        self.buttonNumber = buttonNumber
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.isARepeat = isARepeat
        self.scrollingDeltaX = scrollingDeltaX
        self.scrollingDeltaY = scrollingDeltaY
        self.hasPreciseScrollingDeltas = precise
        self.trackingArea = trackingArea
    }

    /// Modifier keys held right now (from the last input event GTK delivered).
    public internal(set) static var modifierFlags: ModifierFlags = []
    /// Mouse buttons held right now, as a bit set (bit 0 = left).
    public internal(set) static var pressedMouseButtons = 0
    /// Pointer position in screen coordinates (bottom-left origin).
    @preconcurrency @MainActor public static var mouseLocation: NSPoint { WindowPlacement.shared.pointerLocation() ?? lastMouseLocation }
    static var lastMouseLocation = NSPoint.zero

    public static var doubleClickInterval: TimeInterval { 0.4 }

    public static func addLocalMonitorForEvents(matching mask: EventTypeMask,
                                                handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let monitor = LocalMonitor(mask: mask, handler: handler)
        localMonitors.append(monitor)
        return monitor
    }

    public static func addGlobalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        nil  // other apps' events are not visible on Wayland
    }

    public static func removeMonitor(_ monitor: Any) {
        localMonitors.removeAll { $0 === monitor as AnyObject }
    }

    public struct EventTypeMask: OptionSet, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        init(_ type: EventType) { rawValue = 1 << type.rawValue }
        public static let leftMouseDown = EventTypeMask(.leftMouseDown)
        public static let leftMouseUp = EventTypeMask(.leftMouseUp)
        public static let rightMouseDown = EventTypeMask(.rightMouseDown)
        public static let rightMouseUp = EventTypeMask(.rightMouseUp)
        public static let mouseMoved = EventTypeMask(.mouseMoved)
        public static let leftMouseDragged = EventTypeMask(.leftMouseDragged)
        public static let keyDown = EventTypeMask(.keyDown)
        public static let keyUp = EventTypeMask(.keyUp)
        public static let flagsChanged = EventTypeMask(.flagsChanged)
        public static let scrollWheel = EventTypeMask(.scrollWheel)
        public static let any = EventTypeMask(rawValue: .max)
    }

    final class LocalMonitor {
        let mask: EventTypeMask
        let handler: (NSEvent) -> NSEvent?
        init(mask: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) { self.mask = mask; self.handler = handler }
    }
    static var localMonitors: [LocalMonitor] = []

    /// Runs local monitors; nil means a monitor swallowed the event.
    static func filter(_ event: NSEvent) -> NSEvent? {
        var current: NSEvent? = event
        for monitor in localMonitors where monitor.mask.contains(EventTypeMask(event.type)) {
            guard let e = current else { return nil }
            current = monitor.handler(e)
        }
        return current
    }
}

@preconcurrency @MainActor
open class NSResponder: NSObject {
    open weak var nextResponder: NSResponder?

    public override init() { super.init() }

    open var acceptsFirstResponder: Bool { false }
    open func becomeFirstResponder() -> Bool { true }
    open func resignFirstResponder() -> Bool { true }

    open func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    open func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
    open func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    open func mouseMoved(with event: NSEvent) { nextResponder?.mouseMoved(with: event) }
    open func mouseEntered(with event: NSEvent) { nextResponder?.mouseEntered(with: event) }
    open func mouseExited(with event: NSEvent) { nextResponder?.mouseExited(with: event) }
    open func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
    open func rightMouseDragged(with event: NSEvent) { nextResponder?.rightMouseDragged(with: event) }
    open func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
    open func otherMouseDown(with event: NSEvent) { nextResponder?.otherMouseDown(with: event) }
    open func otherMouseDragged(with event: NSEvent) { nextResponder?.otherMouseDragged(with: event) }
    open func otherMouseUp(with event: NSEvent) { nextResponder?.otherMouseUp(with: event) }
    open func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    open func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }
    open func keyUp(with event: NSEvent) { nextResponder?.keyUp(with: event) }
    open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
    open func cursorUpdate(with event: NSEvent) {}

    // Standard actions sent down the responder chain.
    open func copy(_ sender: Any?) {}
    open func paste(_ sender: Any?) {}
    open func cut(_ sender: Any?) {}
    open func delete(_ sender: Any?) {}
    open func cancelOperation(_ sender: Any?) {}
}

/// Region of a view that reports enter/exit/move and cursor updates.
open class NSTrackingArea {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mouseEnteredAndExited = Options(rawValue: 0x01)
        public static let mouseMoved = Options(rawValue: 0x02)
        public static let cursorUpdate = Options(rawValue: 0x04)
        public static let activeWhenFirstResponder = Options(rawValue: 0x10)
        public static let activeInKeyWindow = Options(rawValue: 0x20)
        public static let activeInActiveApp = Options(rawValue: 0x40)
        public static let activeAlways = Options(rawValue: 0x80)
        public static let assumeInside = Options(rawValue: 0x100)
        public static let inVisibleRect = Options(rawValue: 0x200)
        public static let enabledDuringMouseDrag = Options(rawValue: 0x400)
    }

    public let rect: NSRect
    public let options: Options
    public weak var owner: AnyObject?
    public let userInfo: [AnyHashable: Any]?
    var inside = false

    public init(rect: NSRect, options: Options, owner: AnyObject?, userInfo: [AnyHashable: Any]?) {
        self.rect = rect
        self.options = options
        self.owner = owner
        self.userInfo = userInfo
    }
}
