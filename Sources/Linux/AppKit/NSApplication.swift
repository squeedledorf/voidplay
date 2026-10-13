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

    public weak var delegate: NSApplicationDelegate?
    private var loop: OpaquePointer?

    public private(set) var isRunning = false

    public init() {}

    open func run() {
        gtk_init()
        // gtk_init adopts the environment's locale; libmpv (and number parsing in skins) needs
        // LC_NUMERIC "C", or a locale with decimal commas breaks both.
        setlocale(LC_NUMERIC, "C")
        MainLoop.install()
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

    open func terminate(_ sender: Any?) {
        let note = Notification(name: Self.willTerminateNotification, object: self)
        delegate?.applicationWillTerminate(note)
        NotificationCenter.default.post(note)
        exit(0)
    }
}
