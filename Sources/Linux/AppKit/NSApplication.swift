import Foundation
import CGtk
import QuartzCore

public protocol NSApplicationDelegate: AnyObject {
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationWillTerminate(_ notification: Notification)
}

extension NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {}
    public func applicationWillTerminate(_ notification: Notification) {}
}

/// The application object over GTK: `run()` starts GTK and GLib's main loop (with Foundation's
/// run loop folded in) and tells the delegate it launched.
@preconcurrency @MainActor
open class NSApplication {
    public static let shared = NSApplication()

    public struct ModalResponse: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let OK = ModalResponse(rawValue: 1)
        public static let cancel = ModalResponse(rawValue: 0)
        public static let alertFirstButtonReturn = ModalResponse(rawValue: 1000)
        public static let alertSecondButtonReturn = ModalResponse(rawValue: 1001)
        public static let alertThirdButtonReturn = ModalResponse(rawValue: 1002)
    }

    public static let didFinishLaunchingNotification = Notification.Name("NSApplicationDidFinishLaunchingNotification")
    public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")
    public static let didChangeScreenParametersNotification = Notification.Name("NSApplicationDidChangeScreenParametersNotification")

    public weak var delegate: NSApplicationDelegate?
    private var loop: OpaquePointer?

    public private(set) var isRunning = false

    public init() {}

    open func run() {
        // Names the app for the desktop: the Wayland app id (Hyprland "class") and the X11 WM_CLASS.
        g_set_prgname("voidplay")
        gtk_init()
        // gtk_init adopts the environment's locale; libmpv (and number parsing in skins) needs
        // LC_NUMERIC "C", or a locale with decimal commas breaks both.
        setlocale(LC_NUMERIC, "C")
        MainLoop.install()
        // Logout, `kill` and Ctrl+C quit like the Quit command, so settings reach disk.
        for signal in [SIGTERM, SIGINT, SIGHUP] {
            g_unix_signal_add(signal, { _ in
                MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
                return 0
            }, nil)
        }
        CALayer.didChange = { NSApplication.scheduleLayerRedraw() }
        isRunning = true
        let launched = Notification(name: Self.didFinishLaunchingNotification, object: self)
        delegate?.applicationDidFinishLaunching(launched)
        NotificationCenter.default.post(launched)
        loop = g_main_loop_new(nil, 0)
        g_main_loop_run(loop)
    }

    private static var layerRedrawPending = false

    /// Layer changes (contents, geometry, animations) repaint the visible windows on the next pass.
    nonisolated static func scheduleLayerRedraw() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !layerRedrawPending else { return }
                layerRedrawPending = true
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        layerRedrawPending = false
                        for window in NSWindow.all where window.isVisible { window.viewNeedsDisplay() }
                    }
                }
            }
        }
    }

    /// The app's windows (creation order).
    open var windows: [NSWindow] { NSWindow.all }

    /// Whether one of our windows has the focus.
    open var isActive: Bool { NSWindow.all.contains { $0.isKeyWindow } }

    /// The input event being handled now (set while a window routes it).
    open internal(set) var currentEvent: NSEvent?

    /// Menu bar and Dock hiding: the compositor's business here.
    public struct PresentationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let autoHideDock = PresentationOptions(rawValue: 1 << 0)
        public static let autoHideMenuBar = PresentationOptions(rawValue: 1 << 2)
    }
    open var presentationOptions: PresentationOptions = []

    /// No nested event loop for tracking here: the caller sees no event (the press has already
    /// been delivered through the normal path).
    /// ponytail: a real wait would pump GTK until a matching event; nothing needs it yet.
    open func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?, inMode mode: RunLoop.Mode,
                        dequeue: Bool) -> NSEvent? { nil }

    /// The action to `target`, or along the key window's responder chain, then the delegate.
    @discardableResult
    open func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        if let target { return SelectorRegistry.invoke(action, on: target as AnyObject, sender: sender) }
        var responder: NSResponder? = NSWindow.all.first { $0.isKeyWindow }?.firstResponder
        while let current = responder {
            if SelectorRegistry.invoke(action, on: current, sender: sender) { return true }
            responder = current.nextResponder
        }
        if let delegate { return SelectorRegistry.invoke(action, on: delegate, sender: sender) }
        return false
    }

    open func terminate(_ sender: Any?) {
        let note = Notification(name: Self.willTerminateNotification, object: self)
        delegate?.applicationWillTerminate(note)
        NotificationCenter.default.post(note)
        // Darwin's cfprefsd saves defaults on its own; Foundation here only writes on sync.
        UserDefaults.standard.synchronize()
        exit(0)
    }
}

extension RunLoop.Mode {
    /// AppKit's mode while a control tracks the mouse; nothing runs in it here.
    public static let eventTracking = RunLoop.Mode("NSEventTrackingRunLoopMode")
}
