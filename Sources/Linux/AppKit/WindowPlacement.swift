import Foundation
import CGtk
import CX11

/// Puts windows where AppKit code asks. Wayland gives clients no say over placement, so each
/// desktop needs its own route; the base class lets the compositor decide (no docking/snapping).
@preconcurrency @MainActor
class WindowPlacement {
    static let shared: WindowPlacement = {
        let env = ProcessInfo.processInfo.environment
        if let display = gdk_display_get_default(), cx11_is_x11_display(display) != 0 { return X11Placement() }
        if env["HYPRLAND_INSTANCE_SIGNATURE"] != nil, let ipc = HyprlandIPC() { return HyprlandPlacement(ipc: ipc) }
        return WindowPlacement()
    }()

    /// The window's surface exists; find it and apply `frame`.
    func windowDidMap(_ window: NSWindow) {}
    func windowDidShow(_ window: NSWindow) {}
    func windowDidHide(_ window: NSWindow) {}
    /// Move (and resize) to `window.frame`.
    func place(_ window: NSWindow, resized: Bool) {}
    /// Pointer in AppKit screen coordinates, when the desktop exposes it.
    func pointerLocation() -> NSPoint? { nil }
    func reservedInsets(forMonitor name: String) -> (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        (0, 0, 0, 0)
    }
}

// MARK: - Hyprland

/// Hyprland's request socket: one request per connection, reply until EOF.
final class HyprlandIPC: Sendable {
    let path: String

    init?() {
        let env = ProcessInfo.processInfo.environment
        guard let signature = env["HYPRLAND_INSTANCE_SIGNATURE"] else { return nil }
        let runtime = env["XDG_RUNTIME_DIR"] ?? "/run/user/\(getuid())"
        path = "\(runtime)/hypr/\(signature)/.socket.sock"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
    }

    @discardableResult
    func request(_ message: String) -> Data? {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            path.utf8CString.prefix(capacity - 1).enumerated().forEach { buffer[$0.offset] = UInt8(bitPattern: $0.element) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        let bytes = Array(message.utf8)
        guard write(fd, bytes, bytes.count) == bytes.count else { return nil }
        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            reply.append(buffer, count: n)
        }
        return reply
    }

    func json(_ message: String) -> Any? {
        request("j/" + message).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
}

final class HyprlandPlacement: WindowPlacement {
    let ipc: HyprlandIPC

    init(ipc: HyprlandIPC) { self.ipc = ipc }

    override func windowDidMap(_ window: NSWindow) { resolve(window, attempt: 0) }

    /// Finds this window among Hyprland's clients by its placement token (retrying while
    /// Hyprland catches up with the new surface), then floats it, places it, and shows the real title.
    private func resolve(_ window: NSWindow, attempt: Int) {
        guard window.placementID == nil else { place(window, resized: true); return }
        let clients = ipc.json("clients") as? [[String: Any]] ?? []
        let pid = Int(getpid())
        if let client = clients.first(where: { $0["pid"] as? Int == pid && $0["title"] as? String == window.placementToken }),
           let address = client["address"] as? String {
            window.placementID = address
            gtk_window_set_title(window.gtkWindowPtr, window.title)
            var batch = ["dispatch setfloating address:\(address)"]
            if !window.styleMask.contains(.titled) {
                // Skinned windows draw their own frame: no border, rounding, shadow or blur from Hyprland.
                for prop in ["bordersize 0", "rounding 0", "noshadow 1", "noblur 1", "decorate 0"] {
                    batch.append("setprop address:\(address) \(prop)")
                }
            }
            ipc.request("[[BATCH]]" + batch.joined(separator: ";"))
            place(window, resized: true)
            return
        }
        guard attempt < 80 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self, weak window] in
            guard let self, let window else { return }
            self.resolve(window, attempt: attempt + 1)
        }
    }

    override func place(_ window: NSWindow, resized: Bool) {
        guard let address = window.placementID else { return }
        let topLeft = NSScreen.layoutTopLeft(of: window.frame)
        var batch = ["dispatch movewindowpixel exact \(Int(topLeft.x.rounded())) \(Int(topLeft.y.rounded())),address:\(address)"]
        if resized {
            batch.append("dispatch resizewindowpixel exact \(Int(window.frame.width)) \(Int(window.frame.height)),address:\(address)")
        }
        ipc.request("[[BATCH]]" + batch.joined(separator: ";"))
        window.windowWasMovedByApp()
    }

    override func pointerLocation() -> NSPoint? {
        guard let pos = ipc.json("cursorpos") as? [String: Any],
              let x = (pos["x"] as? NSNumber)?.doubleValue, let y = (pos["y"] as? NSNumber)?.doubleValue else { return nil }
        return NSPoint(x: x, y: NSScreen.primaryHeight - y)
    }

    override func reservedInsets(forMonitor name: String) -> (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        guard let monitors = ipc.json("monitors") as? [[String: Any]],
              let monitor = monitors.first(where: { $0["name"] as? String == name }),
              let reserved = monitor["reserved"] as? [NSNumber], reserved.count == 4 else { return (0, 0, 0, 0) }
        let r = reserved.map { CGFloat($0.doubleValue) }
        return (r[0], r[1], r[2], r[3])
    }
}

// MARK: - X11 (X sessions, XWayland with GDK_BACKEND=x11, Xvfb tests)

final class X11Placement: WindowPlacement {
    private var xdisplay: OpaquePointer? {
        gdk_display_get_default().flatMap { gdk_x11_display_get_xdisplay($0) }
    }

    private func xid(_ window: NSWindow) -> Window? {
        guard let native = gtk_widget_get_native(window.gtkWindow),
              let surface = gtk_native_get_surface(native) else { return nil }
        return gdk_x11_surface_get_xid(surface)
    }

    override func windowDidMap(_ window: NSWindow) {
        window.placementID = "x11"
        gtk_window_set_title(window.gtkWindowPtr, window.title)
        place(window, resized: true)
    }

    override func place(_ window: NSWindow, resized: Bool) {
        guard window.placementID != nil, let display = xdisplay, let id = xid(window) else { return }
        let scale = Double(window.backingScaleFactor)
        let topLeft = NSScreen.layoutTopLeft(of: window.frame)
        XMoveWindow(display, id, Int32(topLeft.x * scale), Int32(topLeft.y * scale))
        XFlush(display)
        window.windowWasMovedByApp()
    }

    override func pointerLocation() -> NSPoint? {
        guard let display = xdisplay else { return nil }
        let root = XDefaultRootWindow(display)
        var rootReturn: Window = 0, child: Window = 0
        var rootX: Int32 = 0, rootY: Int32 = 0, winX: Int32 = 0, winY: Int32 = 0
        var mask: UInt32 = 0
        guard XQueryPointer(display, root, &rootReturn, &child, &rootX, &rootY, &winX, &winY, &mask) != 0 else { return nil }
        let scale = Double(NSScreen.screens.first?.backingScaleFactor ?? 1)
        return NSPoint(x: Double(rootX) / scale, y: NSScreen.primaryHeight - Double(rootY) / scale)
    }
}
