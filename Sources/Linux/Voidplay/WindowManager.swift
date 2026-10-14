import AppKit
import NullPlayerCore

/// Linux WindowManager: the classic (.wsz) window set — main, equalizer, playlist — with
/// upstream's skin loading, default stacking and docking/snapping, ported from
/// App/WindowManager.swift. Families not yet on Linux (modern, .wal, .wmz, Audion, video)
/// answer as absent. Retired once upstream's WindowManager compiles here.
final class WindowManager {
    static let shared = WindowManager()

    lazy var audioEngine = AudioEngine()

    private(set) var currentSkin: Skin?
    private(set) var currentSkinPath: String?
    static let lastClassicSkinPathKey = "lastClassicSkinPath"

    private(set) var mainWindowController: MainWindowProviding?
    private(set) var playlistWindowController: PlaylistWindowProviding?
    private(set) var equalizerWindowController: EQWindowProviding?
    /// The `.wmz` player while a WMP skin is the UI (WMPMode.swift); nil in classic mode.
    var wmpMainWindowController: WMPMainWindowController?

    // MARK: Preferences (upstream semantics, classic values)

    var timeDisplayMode: TimeDisplayMode = TimeDisplayMode(rawValue: UserDefaults.standard.string(forKey: "timeDisplayMode") ?? "") ?? .elapsed {
        didSet {
            UserDefaults.standard.set(timeDisplayMode.rawValue, forKey: "timeDisplayMode")
            NotificationCenter.default.post(name: .timeDisplayModeDidChange, object: nil)
            NotificationCenter.default.post(name: .timeDisplaySettingsDidChange, object: nil)
        }
    }
    var timeDisplayNumberSystem: TimeDisplayNumberSystem { .modernDefault }
    var uiScaleLevel: UIScaleLevel = .p100
    var classicScaleMultiplier: CGFloat { uiScaleLevel.scaleFactor }
    var isDoubleSize: Bool { uiScaleLevel != .p100 }
    var hideTitleBars: Bool { false }
    var isAlwaysOnTop = false
    var isWindowLayoutLocked = false
    var uiMode: PlayerUIMode { wmpMainWindowController == nil ? .classic : .wmp }
    var isRunningModernUI: Bool { false }
    var isRunningWMPUI: Bool { wmpMainWindowController != nil }
    var isModernUIEnabled: Bool { false }
    var runningControllerFamily: PlayerUIControllerFamily { isRunningWMPUI ? .wmp : .classic }

    var playlistChromeScale: CGFloat {
        if let main = mainWindowController?.window, main.frame.width > 0 { return main.frame.width / Skin.baseMainSize.width }
        return Skin.scaleFactor * classicScaleMultiplier
    }

    var nativeWindowDefaultWidth: CGFloat { Skin.mainWindowSize.width * classicScaleMultiplier }
    func nativeWindowDefaultSize(for window: NSWindow) -> CGSize? { nil }

    // MARK: Hosted surfaces (.wal/.wmz lend frames to our windows; none on Linux yet)

    static let hostedSurfaceStyle: SkinnedSurfaceStyle? = nil
    var hostedSurfaceStyle: SkinnedSurfaceStyle? { nil }
    var hostedBorderWindows: [(window: NSWindow?, fallback: SkinnedSurfaceChrome.Metrics)] { [] }
    var hostedSurfaceBorderInsets: SkinnedSurfaceChrome.Metrics? { nil }
    var hostedSurfaceBordersAreSettled: Bool { true }
    var hostedSurfaceIsStagingSwitch: Bool { false }
    var hostedInteriorSkinKey: String? { nil }
    var hostedInteriorScope: String? { nil }
    func hostedSurfaceFrameArtwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? { nil }
    func hostedSurfaceRenderedFrameArtwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? { nil }
    func hostedSurfaceHasSettledFrameAnswer(for size: CGSize) -> Bool { true }
    func demandHostedSurfaceFrame(for size: CGSize) {}
    func prewarmHostedSurfaceFrames(_ sizes: [CGSize]) {}
    func hostedSurfaceLiveResize(began: Bool, size: CGSize) {}

    // MARK: Video (the video player arrives with the libmpv video stage)

    var isVideoContentActive: Bool { false }
    var isVideoActivePlayback: Bool { false }
    var isVideoCastingActive: Bool { false }
    var isVideoPlaying: Bool { false }
    var videoPlaybackState: PlaybackState { .stopped }
    var videoDuration: TimeInterval { 0 }
    var videoCurrentTime: TimeInterval { 0 }
    var currentVideoTitle: String? { nil }
    func toggleVideoPlayPause() {}
    func stopVideo() {}
    func skipVideoForward(_ seconds: TimeInterval = 10) {}
    func skipVideoBackward(_ seconds: TimeInterval = 10) {}
    func seekVideo(to time: TimeInterval) {}
    func setVideoVolume(_ volume: Float) {}

    // Windows that are not on Linux yet.
    func toggleSpectrum() {}
    func toggleProjectM() {}
    func togglePlexBrowser() {}

    // MARK: Skins

    @discardableResult
    func loadSkin(from url: URL, userDefaults: UserDefaults = .standard) -> Bool {
        do {
            let skin = try SkinLoader.shared.load(from: url)
            currentSkin = skin
            currentSkinPath = url.path
            userDefaults.set(url.path, forKey: Self.lastClassicSkinPathKey)
            notifySkinChanged()
            return true
        } catch {
            NSLog("Failed to load skin: \(error)")
            return false
        }
    }

    /// Last skin used, else the bundled default (as upstream's loadDefaultSkin).
    func loadDefaultSkin() {
        if let last = UserDefaults.standard.string(forKey: Self.lastClassicSkinPathKey),
           FileManager.default.fileExists(atPath: last),
           let skin = try? SkinLoader.shared.load(from: URL(fileURLWithPath: last)) {
            currentSkin = skin
            currentSkinPath = last
            return
        }
        if let bundled = Self.bundledSkinURL("NullPlayer-Silver"),
           let skin = try? SkinLoader.shared.load(from: bundled) {
            currentSkin = skin
            return
        }
        currentSkin = SkinLoader.shared.loadDefault()
    }

    /// Where downloaded skins live (`~/.local/share/Voidplay/Skins`), created on first use.
    static var userSkinsDirectory: URL {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
                      ?? NSHomeDirectory() + "/.local/share")
            .appendingPathComponent(ClientIdentity.dataDirectoryName).appendingPathComponent("Skins")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func bundledSkinURL(_ name: String) -> URL? {
        Bundle.module.url(forResource: "Resources/Skins/\(name)", withExtension: "wsz")
    }

    private func notifySkinChanged() {
        mainWindowController?.skinDidChange()
        playlistWindowController?.skinDidChange()
        equalizerWindowController?.skinDidChange()
        NotificationCenter.default.post(name: .classicSkinDidChange, object: nil)
    }

    // MARK: Windows

    func showMainWindow(reveal: Bool = true) {
        if mainWindowController == nil { mainWindowController = MainWindowController() }
        if reveal { mainWindowController?.showWindow(nil) }
        mainWindowController?.windowVisibilityDidChange()
    }

    var isPlaylistVisible: Bool { playlistWindowController?.window?.isVisible ?? false }
    var isEqualizerVisible: Bool { equalizerWindowController?.window?.isVisible ?? false }

    func showEqualizer() {
        if equalizerWindowController == nil { equalizerWindowController = EQWindowController() }
        equalizerWindowController?.showWindow(nil)
        notifyMainWindowVisibilityChanged()
    }

    func showPlaylist() {
        if playlistWindowController == nil { playlistWindowController = PlaylistWindowController() }
        playlistWindowController?.showWindow(nil)
        notifyMainWindowVisibilityChanged()
    }

    func toggleEqualizer() {
        if isEqualizerVisible { equalizerWindowController?.window?.orderOut(nil) } else { showEqualizer() }
        notifyMainWindowVisibilityChanged()
    }

    func togglePlaylist() {
        if isPlaylistVisible { playlistWindowController?.window?.orderOut(nil) } else { showPlaylist() }
        notifyMainWindowVisibilityChanged()
    }

    func notifyMainWindowVisibilityChanged() {
        mainWindowController?.windowVisibilityDidChange()
        mainWindowController?.setNeedsDisplay()
    }

    func handleCenterStackWindowWillClose(_ window: NSWindow) {}

    /// Main window centred, then the equalizer and playlist stacked under it (upstream's layout).
    func snapToDefaultPositions() {
        guard let main = mainWindowController?.window, let screen = main.screen ?? NSScreen.main else { return }
        let size = main.frame.size
        let mainFrame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                               width: size.width, height: size.height)
        main.setFrame(mainFrame, display: true)
        var nextY = mainFrame.minY
        for window in [equalizerWindowController?.window, playlistWindowController?.window].compactMap({ $0 }) where window.isVisible {
            nextY -= window.frame.height
            window.setFrameOrigin(NSPoint(x: mainFrame.minX, y: nextY))
        }
    }

    func bringAllWindowsToFront(keepingWindowOnTop preferredTopWindow: NSWindow? = nil) {}
    func miniaturizeAllManagedWindows() { managedWindows.forEach { $0.miniaturize(nil) } }
    func attachDockedWindowsForMiniaturize(mainWindow: NSWindow) {}
    func detachDockedWindowsAfterDeminiaturize(mainWindow: NSWindow) {}

    private var managedWindows: [NSWindow] {
        [mainWindowController?.window, equalizerWindowController?.window, playlistWindowController?.window]
            .compactMap { $0 }.filter(\.isVisible)
    }

    // MARK: Docking and snapping (upstream's algorithm)

    private let snapThreshold: CGFloat = 15
    private let dockThreshold: CGFloat = 3
    private var draggingWindow: NSWindow?
    var isWindowDragInProgress: Bool { draggingWindow != nil && (NSEvent.pressedMouseButtons & 0x1) != 0 }
    private var dockedWindowsToMove: [NSWindow] = []
    private var dockedWindowOffsets: [ObjectIdentifier: NSPoint] = [:]
    private var isSnappingWindow = false
    private var isMovingDockedWindows = false

    func isWindowDocked(_ window: NSWindow) -> Bool { !findDockedWindows(to: window).isEmpty }

    func windowWillStartDragging(_ window: NSWindow, fromTitleBar: Bool = false) {
        draggingWindow = window
        dockedWindowsToMove = findDockedWindows(to: window)
        dockedWindowOffsets = Dictionary(uniqueKeysWithValues: dockedWindowsToMove.map {
            (ObjectIdentifier($0), NSPoint(x: $0.frame.minX - window.frame.minX, y: $0.frame.minY - window.frame.minY))
        })
    }

    /// Hold-to-separate priming (upstream): docked groups move together; separating them comes later.
    func windowWillPrimeDragging(_ window: NSWindow) {}
    func windowDidCancelDragPrime(_ window: NSWindow) {}

    func windowDidFinishDragging(_ window: NSWindow) {
        guard draggingWindow === window else { return }
        draggingWindow = nil
        dockedWindowsToMove = []
        dockedWindowOffsets = [:]
    }

    func applySnappedPosition(_ window: NSWindow, to position: NSPoint) {
        guard !isSnappingWindow, position != window.frame.origin else { return }
        isSnappingWindow = true
        defer { isSnappingWindow = false }
        window.setFrameOrigin(position)
    }

    /// Snaps `newOrigin` and carries docked peers along while the window is dragged.
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        if isSnappingWindow || isMovingDockedWindows { return newOrigin }
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        guard dragging else { return applySnapping(for: window, to: newOrigin) }
        if draggingWindow !== window { windowWillStartDragging(window) }
        let snapped = applySnapping(for: window, to: newOrigin)
        isMovingDockedWindows = true
        for docked in dockedWindowsToMove {
            if let offset = dockedWindowOffsets[ObjectIdentifier(docked)] {
                docked.setFrameOrigin(NSPoint(x: snapped.x + offset.x, y: snapped.y + offset.y))
            }
        }
        isMovingDockedWindows = false
        return snapped
    }

    private func applySnapping(for window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        let frame = NSRect(origin: newOrigin, size: window.frame.size)
        var bestX: (distance: CGFloat, value: CGFloat)?
        var bestY: (distance: CGFloat, value: CGFloat)?
        func offerX(_ d: CGFloat, _ v: CGFloat, weight: CGFloat = 1) {
            if d < snapThreshold, bestX == nil || d < bestX!.distance * weight { bestX = (d, v) }
        }
        func offerY(_ d: CGFloat, _ v: CGFloat, weight: CGFloat = 1) {
            if d < snapThreshold, bestY == nil || d < bestY!.distance * weight { bestY = (d, v) }
        }
        func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool {
            a1 > b0 - snapThreshold && a0 < b1 + snapThreshold
        }

        if let screen = window.screen ?? NSScreen.main {
            let s = screen.visibleFrame
            offerX(abs(frame.minX - s.minX), s.minX)
            offerX(abs(frame.maxX - s.maxX), s.maxX - frame.width)
            offerY(abs(frame.minY - s.minY), s.minY)
            offerY(abs(frame.maxY - s.maxY), s.maxY - frame.height)
        }
        for other in managedWindows where other !== window && !dockedWindowsToMove.contains(where: { $0 === other }) {
            let o = other.frame
            if overlap(frame.minY, frame.maxY, o.minY, o.maxY) {
                offerX(abs(frame.maxX - o.minX), o.minX - frame.width)
                offerX(abs(frame.minX - o.maxX), o.maxX)
                let ll = abs(frame.minX - o.minX), rr = abs(frame.maxX - o.maxX)
                if ll > 0 { offerX(ll, o.minX, weight: 0.8) }
                if rr > 0 { offerX(rr, o.maxX - frame.width, weight: 0.8) }
            }
            if overlap(frame.minX, frame.maxX, o.minX, o.maxX) {
                offerY(abs(frame.minY - o.maxY), o.maxY)
                offerY(abs(frame.maxY - o.minY), o.minY - frame.height)
                let tt = abs(frame.maxY - o.maxY), bb = abs(frame.minY - o.minY)
                if tt > 0 { offerY(tt, o.maxY - frame.height, weight: 0.8) }
                if bb > 0 { offerY(bb, o.minY, weight: 0.8) }
            }
        }
        var snapped = NSPoint(x: bestX?.value ?? newOrigin.x, y: bestY?.value ?? newOrigin.y)
        if let screen = window.screen ?? NSScreen.main {
            snapped.y = min(snapped.y, screen.visibleFrame.maxY - frame.height)
        }
        return snapped
    }

    func findDockedWindows(to window: NSWindow) -> [NSWindow] {
        let candidates = managedWindows
        guard candidates.contains(where: { $0 === window }) else { return [] }
        var docked: [NSWindow] = []
        var queue = [window]
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(window)]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for other in candidates where !seen.contains(ObjectIdentifier(other)) && areWindowsDocked(current, other) {
                docked.append(other)
                queue.append(other)
                seen.insert(ObjectIdentifier(other))
            }
        }
        return docked
    }

    private func areWindowsDocked(_ a: NSWindow, _ b: NSWindow) -> Bool {
        let f1 = a.frame, f2 = b.frame
        let horizontallyAligned = f1.minY < f2.maxY && f1.maxY > f2.minY
        let touchingHorizontally = horizontallyAligned
            && (abs(f1.maxX - f2.minX) <= dockThreshold || abs(f1.minX - f2.maxX) <= dockThreshold)
        let verticallyAligned = f1.minX < f2.maxX && f1.maxX > f2.minX
        let touchingVertically = verticallyAligned
            && (abs(f1.maxY - f2.minY) <= dockThreshold || abs(f1.minY - f2.maxY) <= dockThreshold)
        return touchingHorizontally || touchingVertically
    }
}
