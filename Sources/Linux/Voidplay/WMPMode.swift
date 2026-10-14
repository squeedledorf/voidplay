import AppKit
import NullPlayerCore

/// Windows Media Player (.wmz) mode on Linux: upstream's WMPMainWindowController runs the skin;
/// this is the slice of upstream WindowManager it talks to, and the switch between the classic
/// window set and a WMP skin.
///
/// ponytail: no hosted windows (a .wmz lending its frame to our playlist/library windows), no
/// video surface; those answer "none" until their windows exist on Linux.
extension WindowManager {
    static let skinFamilyKey = "linuxSkinFamily"

    // MARK: Switching

    /// Imports a .wmz into the WMP skin store, selects it and shows it in place of the classic windows.
    func loadWMPSkin(from url: URL) {
        Task { @MainActor in
            do {
                let importer = WMPSkinImporter()
                let installed = try await importer.importSkin(from: url)
                importer.select(installed)
                showWMPMode()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not load skin"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// The selected WMP skin as the UI; classic windows hidden.
    func showWMPMode() {
        for window in [mainWindowController?.window, equalizerWindowController?.window, playlistWindowController?.window] {
            window?.orderOut(nil)
        }
        let controller = wmpMainWindowController ?? WMPMainWindowController()
        wmpMainWindowController = controller
        controller.showWindow(nil)
        controller.reloadSelectedSkin()
        UserDefaults.standard.set("wmp", forKey: Self.skinFamilyKey)
    }

    /// Back to the classic window set (after loading a .wsz).
    func leaveWMPMode() {
        guard let controller = wmpMainWindowController else { return }
        wmpMainWindowController = nil
        controller.window?.orderOut(nil)
        controller.close()
        UserDefaults.standard.set("classic", forKey: Self.skinFamilyKey)
    }

    var launchesInWMPMode: Bool {
        UserDefaults.standard.string(forKey: Self.skinFamilyKey) == "wmp" && WMPSkinImporter().selectedSkinName != nil
    }

    // MARK: What the WMP controller asks of the window manager

    var hostedSkinIdentity: String? { wmpMainWindowController?.loadedSkinURL?.path }
    func forgetSkinWindowPlacement() {}
    func dismissWMPFallbackSurfacesTheSkinProvides() {}
    func hostedWindowTargets(for insets: NSEdgeInsets) -> [CGSize] { [] }
    var hasVisibleHostedWindows: Bool { false }
    func postWindowLayoutDidChange() { NotificationCenter.default.post(name: .windowLayoutDidChange, object: nil) }

    var videoTitle: String? { nil }
    func seekVideoCast(position: Double) {}
    func setVideoCastVolume(_ volume: Float) {}
    var currentVideoPlayerController: VideoPlayerWindowController? { nil }

    func occupiedWindowFrames(excluding excluded: NSWindow? = nil) -> [NSRect] {
        NSApp.windows.compactMap { window in
            guard window !== excluded, window.isVisible, !window.frame.isEmpty else { return nil }
            return window.frame
        }
    }

    /// Where `window` has to move to be reachable, or nil when a screen already shows its top-left.
    func rescuedOrigin(for window: NSWindow) -> NSPoint? {
        let grip = NSRect(x: window.frame.minX, y: window.frame.maxY - 20, width: min(100, window.frame.width), height: 20)
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(grip) }),
              let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return nil }
        return NSPoint(x: min(max(window.frame.minX, screen.minX), screen.maxX - window.frame.width),
                       y: min(max(window.frame.minY, screen.minY), screen.maxY - window.frame.height))
    }

    func ensureAllWindowsOnScreen() {
        for window in NSApp.windows where window.isVisible {
            if let origin = rescuedOrigin(for: window) { window.setFrameOrigin(origin) }
        }
    }

    /// A free spot for a newly opened skin window: left to right, top to bottom over the main
    /// screen, clear of `occupied`; the screen's top-left when nothing is clear.
    /// ponytail: a simple grid walk, not upstream's arrangement tiler.
    func tiledOrigin(for size: NSSize, avoiding occupied: [NSRect]) -> NSPoint? {
        guard let region = NSScreen.main?.visibleFrame else { return nil }
        var y = region.maxY - size.height
        while y >= region.minY {
            var x = region.minX
            while x + size.width <= region.maxX {
                let slot = NSRect(origin: NSPoint(x: x, y: y), size: size)
                if let hit = occupied.first(where: { $0.intersects(slot) }) { x = hit.maxX + 1; continue }
                return slot.origin
            }
            y -= max(size.height / 2, 20)
        }
        return NSPoint(x: region.minX, y: region.maxY - size.height)
    }
}
