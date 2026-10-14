import AppKit
import NullPlayerCore

// Linux answers for upstream services the classic windows reach that are not ported yet.

/// Remember-state restore arrives with upstream's AppStateManager; until then nothing is restored.
final class AppStateManager {
    static let shared = AppStateManager()
    var isEnabled: Bool { false }
}

/// EQ profiles run in upstream's AVAudioUnit graph; the mpv engine has none yet, so no track is marked.
final class EQProfileResolver {
    static let shared = EQProfileResolver()
    static func queueTitle(_ title: String, marked: Bool) -> String { marked ? "∿ \(title)" : title }
    func queueTitle(for track: Track) -> String { Self.queueTitle(track.playlistTitle, marked: false) }
    func fileInfoLine(for track: Track) -> String? { nil }
    func appliesProfile(to track: Track) -> Bool { false }
}

/// EQ profile assignment (an upstream AVAudioUnit feature) has nothing to offer on Linux yet.
enum EQProfileMenu {
    static func addAssignItem(to menu: NSMenu, queueRows: Set<Int>) {}
}

/// The main right-click menu. A Linux build of the essentials until upstream's ContextMenuBuilder
/// (which reaches every window family) compiles here.
/// ponytail: transport, windows, skins and quit only.
enum ContextMenuBuilder {
    /// A `.wal` skin's menu-bar entries (File, Play, Options…) all open the player menu for now.
    /// ponytail: upstream builds a menu per entry; port ContextMenuBuilder's builders to split them.
    static func winampModernMenuBarMenu(for identifier: String) -> NSMenu? {
        guard WindowManager.shared.uiMode.controllerFamily == .winampModern else { return nil }
        return buildMenu()
    }

    /// Visualization engines: none on Linux yet.
    static func buildVisualizationsMenu() -> NSMenu { NSMenu(title: "Visualizations") }

    static func buildMenu(includeOutputDevices: Bool = true, includeRepeatShuffle: Bool = true) -> NSMenu {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        let menu = NSMenu()
        func item(_ title: String, on: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.state = on ? .on : .off
            item.isEnabled = enabled
            item.handler = { _ in action() }
            return item
        }

        menu.addItem(item("Open File…") { openFiles() })
        menu.addItem(item("Open URL…") { openURL() })
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(engine.state == .playing ? "Pause" : "Play") {
            engine.state == .playing ? engine.pause() : engine.play()
        })
        menu.addItem(item("Stop") { engine.stop() })
        menu.addItem(item("Previous") { engine.previous() })
        menu.addItem(item("Next") { engine.next() })
        if includeRepeatShuffle {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(item("Repeat", on: engine.repeatEnabled) { engine.repeatEnabled.toggle() })
            menu.addItem(item("Shuffle", on: engine.shuffleEnabled) { engine.shuffleEnabled.toggle() })
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Equalizer", on: wm.isEqualizerVisible) { wm.toggleEqualizer() })
        menu.addItem(item("Playlist Editor", on: wm.isPlaylistVisible) { wm.togglePlaylist() })
        menu.addItem(item("Snap Windows to Default Positions") { wm.snapToDefaultPositions() })
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Load Skin…") { loadSkin() })
        if includeOutputDevices {
            let outputs = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "Output Device")
            submenu.addItem(item("System Default") { engine.setOutputDevice(nil) })
            for device in AudioOutputManager.shared.outputDevices {
                submenu.addItem(item(device.name, on: AudioOutputManager.shared.currentDeviceID == device.id) {
                    engine.setOutputDevice(device.id)
                })
            }
            outputs.submenu = submenu
            menu.addItem(outputs)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit \(ClientIdentity.productName)") { NSApplication.shared.terminate(nil) })
        return menu
    }

    static func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let engine = WindowManager.shared.audioEngine
        engine.loadFiles(panel.urls)
        engine.play()
    }

    /// A stream, file URL, or YouTube video/playlist link (expanded to one track per video).
    private static func openURL() {
        let alert = NSAlert()
        alert.messageText = "Open URL"
        alert.informativeText = "A stream or file address, or a YouTube video or playlist link:"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "https://www.youtube.com/playlist?list=…"
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else { return }
        let engine = WindowManager.shared.audioEngine
        engine.loadFiles([url])
        if !YouTubeLinks.isYouTube(url) { engine.play() }  // YouTube links start once expanded
    }

    private static func loadSkin() {
        let panel = NSOpenPanel()
        panel.directoryURL = WindowManager.userSkinsDirectory
        panel.allowedFileExtensions = ["wsz", "zip", "wmz", "wal"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WindowManager.shared.loadAnySkin(from: url)
    }
}

/// Upstream draws a soft shadow from the skin's alpha; Linux leaves shadows to the compositor.
private var skinShadowFlags: [ObjectIdentifier: Bool] = [:]
extension NSWindow {
    var hasSkinShadow: Bool {
        get { skinShadowFlags[ObjectIdentifier(self)] ?? false }
        set { skinShadowFlags[ObjectIdentifier(self)] = newValue }
    }
}

/// The main menu's actions a `.wal` skin's own buttons call.
final class MenuActions {
    static let shared = MenuActions()
    func openFile() { ContextMenuBuilder.openFiles() }
    /// ClassicPro engine import (for cPro skins): later.
    func importClassicProEngineFromFile() {}
}
