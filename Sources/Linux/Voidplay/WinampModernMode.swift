import AppKit
import NullPlayerCore

/// Winamp Modern (.wal) mode on Linux: upstream's WinampModernMainWindowController runs the skin
/// and becomes the main window controller, as upstream does; this is the slice of upstream
/// WindowManager it talks to (App/WindowManager.swift, "Winamp Modern surface routing").
///
/// ponytail: none of NullPlayer's own feature windows (spectrum, Cava, ProjectM, Plex…) exist on
/// Linux yet, so the hosted-window routes answer "not open" and the classic fallbacks do nothing
/// beyond the playlist and equalizer.
extension WindowManager {
    var winampModernMainWindowController: WinampModernMainWindowController? {
        mainWindowController as? WinampModernMainWindowController
    }

    private var winampModernSurfaces: WinampModernSurfaceCoordinator? { winampModernMainWindowController?.surfaceCoordinator }

    // MARK: Switching

    /// Imports a .wal into the skin store (which selects it) and shows it as the UI.
    func loadWinampModernSkin(from url: URL) {
        do {
            let imported = try WinampModernSkinImporter.shared.importContainer(at: url)
            if let controller = winampModernMainWindowController {
                controller.loadSkin(at: imported.archiveURL)
                ensureAllWindowsOnScreen()
            } else {
                showWinampModernMode()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not load skin"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// The selected .wal skin as the UI, in place of the classic or WMP windows.
    func showWinampModernMode() {
        leaveWMPMode()
        guard winampModernMainWindowController == nil else { return }
        for window in [mainWindowController?.window, equalizerWindowController?.window, playlistWindowController?.window] {
            window?.orderOut(nil)
        }
        // The new controller loads the selected skin as it is made.
        let controller = WinampModernMainWindowController()
        mainWindowController = controller
        // Centred at the skin's size: the controller centred its placeholder, then grew it.
        controller.window?.center()
        controller.showWindow(nil)
        UserDefaults.standard.set("wal", forKey: Self.skinFamilyKey)
    }

    /// Back to the classic window set; the classic main window is made afresh by `showMainWindow`.
    func leaveWinampModernMode() {
        guard let controller = winampModernMainWindowController else { return }
        // Cleared first: closing the window must not read as quitting the player.
        mainWindowController = nil
        controller.prepareForUITeardown()
        controller.window?.orderOut(nil)
        controller.close()
        UserDefaults.standard.set("classic", forKey: Self.skinFamilyKey)
    }

    var launchesInWinampModernMode: Bool {
        UserDefaults.standard.string(forKey: Self.skinFamilyKey) == "wal" && WinampModernSkinImporter.shared.selectedSkin() != nil
    }

    // MARK: Surface routing (the skin's own playlist, equalizer… before ours)

    /// Shows or toggles the skin's own copy of `kind`; false when the skin has none.
    @discardableResult
    func routeWinampModernSurface(_ kind: WinampModernComponentKind, toggle: Bool) -> Bool {
        guard let coordinator = winampModernSurfaces, coordinator.handles(kind) else { return false }
        if toggle { coordinator.toggleSurface(kind) } else { coordinator.showSurface(kind) }
        notifyMainWindowVisibilityChanged()
        postWindowLayoutDidChange()
        return true
    }

    func winampModernSurfaceIsVisible(_ kind: WinampModernComponentKind) -> Bool? {
        guard let coordinator = winampModernSurfaces, coordinator.handles(kind) else { return nil }
        return coordinator.isSurfaceVisible(kind)
    }

    var winampModernSurfaceStyle: WinampModernSurfaceStyle? {
        winampModernMainWindowController?.currentPalette.map(WinampModernSurfaceStyle.init(palette:))
    }

    func refreshWinampModernSurfaces() {
        winampModernSurfaces?.surfaceContentDidChange()
        equalizerWindowController?.window?.contentView?.needsDisplay = true
    }

    func winampModernSurfaceVisibility() -> [WinampModernComponentKind: Bool] {
        guard let coordinator = winampModernSurfaces else { return [:] }
        var states: [WinampModernComponentKind: Bool] = [:]
        for kind in [WinampModernComponentKind.playlist, .equalizer] {
            if coordinator.handles(kind) {
                guard !coordinator.isEmbedded(kind) else { continue }
                states[kind] = coordinator.isSurfaceVisible(kind)
            } else if kind == .playlist {
                states[kind] = playlistWindowController?.window?.isVisible == true
            }
        }
        return states
    }

    /// After a skin change: the playlist/equalizer open again where the user had them open.
    func restoreWinampModernSurfaceVisibility(_ states: [WinampModernComponentKind: Bool]) {
        guard let coordinator = winampModernSurfaces else { return }
        for (kind, wasOpen) in states {
            let skinOwned = coordinator.handles(kind)
            if skinOwned, kind == .playlist, playlistWindowController?.window?.isVisible == true {
                playlistWindowController?.window?.orderOut(nil)
            } else if skinOwned, kind == .equalizer, equalizerWindowController?.window?.isVisible == true {
                equalizerWindowController?.window?.orderOut(nil)
            }
            let isOpen = kind == .playlist ? isPlaylistVisible : isEqualizerVisible
            if wasOpen, !isOpen {
                kind == .playlist ? showPlaylist() : showEqualizer()
            } else if !wasOpen, isOpen, skinOwned, !coordinator.isEmbedded(kind) {
                routeWinampModernSurface(kind, toggle: true)
            }
        }
    }

    /// The skin has no window for `kind`: ours stands in.
    func showClassicSurfaceForWinampModern(_ kind: WinampModernComponentKind, showOnly: Bool) {
        switch kind {
        case .playlist: showOnly ? showClassicPlaylist() : toggleClassicPlaylist()
        case .equalizer: showOnly ? showClassicEqualizer() : toggleClassicEqualizer()
        default: break
        }
    }

    // MARK: Hosted feature windows (none on Linux yet)

    func openWinampModernHostedWindowIDs() -> Set<WinampModernHostedWindowID> { [] }
    func rehomeWinampModernHostedWindows(_ ids: Set<WinampModernHostedWindowID>) {}
    func showClassicHostedWindowForWinampModern(_ id: WinampModernHostedWindowID, showOnly: Bool) {
        if id == .equalizer { showOnly ? showClassicEqualizer() : toggleClassicEqualizer() }
    }
    func hostedWindowVisibilityDidChange(id: WinampModernHostedWindowID, visible: Bool, transitionFrame: NSRect) {
        notifyMainWindowVisibilityChanged()
        postWindowLayoutDidChange()
    }
    func winampModernHostedWindowsForArrangement() -> [NSWindow] {
        winampModernMainWindowController?.materializedHostedWindows.map(\.window) ?? []
    }

    func releaseClosedWindowSlots(under window: NSWindow) {
        winampModernMainWindowController?.releaseClosedContainerSlots(under: window.frame, except: window)
    }

    func winampModernTiler() -> WinampModernTiler? {
        guard let player = mainWindowController?.window?.frame,
              let region = (mainWindowController?.window?.screen ?? NSScreen.main)?.visibleFrame else { return nil }
        return WinampModernTiler(playerFrame: player, region: region)
    }

    func restoreMinimizeAllCompanions(mainWindow: NSWindow) {}
    var isPlexBrowserVisible: Bool { false }

    // MARK: Visualization (the skin's own analyzer; MilkDrop and video not yet on Linux)

    func repaintWinampModernVisualization() { winampModernMainWindowController?.repaintVisualization() }
    func setWinampModernSpectrumAnalyzer(_ suite: WinampModernSpectrumAnalyzer) {
        winampModernMainWindowController?.setSpectrumAnalyzer(suite)
    }
    func setWinampModernVisualizationHolderEngine(_ suite: WinampModernSpectrumAnalyzer) {
        winampModernMainWindowController?.setVisualizationHolderEngine(suite)
    }
    func setWinampModernVisualizationHolderMode(_ mode: WasabiVisualizationMode) {
        winampModernMainWindowController?.setVisualizationHolderMode(mode)
    }

    var isProjectMVisible: Bool { winampModernSurfaces?.isSurfaceVisible(.visualization) == true }
    func showProjectMFullscreen() {}
    func stepProjectMPreset(by delta: Int) {}
    func hideLocalVisualizationWindow() {}
    func handOverVisualizationToSkinIfNeeded() {}
    func buildVisualizationMenu() -> NSMenu? { nil }

    var visualizationEngineType: VisualizationType {
        winampModernMainWindowController?.embeddedVisualizationSurface?.engineType
            ?? UserDefaults.standard.string(forKey: "visualizationEngineType").flatMap(VisualizationType.init(rawValue:))
            ?? .projectM
    }
    func switchVisualizationEngine(to type: VisualizationType) {
        UserDefaults.standard.set(type.rawValue, forKey: "visualizationEngineType")
        winampModernMainWindowController?.embeddedVisualizationSurface?.switchEngine(to: type)
    }

    func playVideoTrack(_ track: Track) {}
    func sizeWinampModernVideoSurface(toNativeMultiple multiple: CGFloat) -> Bool {
        winampModernMainWindowController?.sizeVideoSurface(toNativeMultiple: multiple) ?? false
    }
}

extension WindowManager {
    /// Any skin file, by family: .wmz → WMP mode, .wal → Winamp Modern, else a classic skin
    /// (leaving whichever other mode was up).
    func loadAnySkin(from url: URL) {
        switch url.pathExtension.lowercased() {
        case "wmz": leaveWinampModernMode(); loadWMPSkin(from: url)
        case "wal": loadWinampModernSkin(from: url)
        default:
            guard loadSkin(from: url), isRunningWMPUI || winampModernMainWindowController != nil else { return }
            leaveWMPMode()
            leaveWinampModernMode()
            showMainWindow()
            showEqualizer()
            showPlaylist()
            snapToDefaultPositions()
        }
    }
}
