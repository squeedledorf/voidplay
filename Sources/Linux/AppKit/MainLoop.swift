import Foundation
import CGtk

@_silgen_name("_dispatch_get_main_queue_handle_4CF")
private func _dispatch_get_main_queue_handle_4CF() -> Int32

/// Runs Foundation's main RunLoop (Timers, DispatchQueue.main, perform(_:)) inside GLib's main
/// loop, so GTK and upstream code that leans on those share the main thread. A GLib source watches
/// libdispatch's main-queue eventfd and wakes in time for the next Foundation timer; each pass
/// lets CFRunLoop fire due timers and drain the main queue.
enum MainLoop {
    private static var nextTimer = Date.distantFuture
    private static var dispatchTag: gpointer?

    private static var funcs = GSourceFuncs(
        prepare: { _, timeout in
            MainLoop.pump()
            let wait = MainLoop.nextTimer.timeIntervalSinceNow
            timeout?.pointee = wait <= 0 ? 0 : gint(min(wait * 1000, 1000).rounded(.up))
            return wait <= 0 ? 1 : 0
        },
        check: { source in
            let ready = MainLoop.dispatchTag.map { g_source_query_unix_fd(source, $0).rawValue & G_IO_IN.rawValue != 0 } ?? false
            return ready || MainLoop.nextTimer.timeIntervalSinceNow <= 0 ? 1 : 0
        },
        dispatch: { _, _, _ in
            MainLoop.pump()
            return 1  // G_SOURCE_CONTINUE
        },
        finalize: nil, closure_callback: nil, closure_marshal: nil)

    /// Fires due timers and drains the main queue; remembers when the next timer is due.
    private static func pump() {
        nextTimer = RunLoop.main.limitDate(forMode: .default) ?? .distantFuture
    }

    static func install() {
        let source = g_source_new(&funcs, guint(MemoryLayout<GSource>.size))
        dispatchTag = g_source_add_unix_fd(source, _dispatch_get_main_queue_handle_4CF(), G_IO_IN)
        g_source_attach(source, nil)
    }
}

/// Reinterprets one GObject pointer type as another (GTK's C hierarchy has no Swift subtyping).
@inline(__always)
func gcast<In, Out>(_ value: In, to type: Out.Type = Out.self) -> Out { unsafeBitCast(value, to: Out.self) }
