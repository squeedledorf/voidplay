import AppKit
import NullPlayerCore

/// Linux application delegate for the classic window set: forwards engine events to the windows
/// as upstream's App/AppDelegate does, and opens files named on the command line.
final class AppDelegate: NSObject, NSApplicationDelegate, AudioEngineDelegate {
    private let windowManager = WindowManager.shared
    private var isShowingPlayFailureAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowManager.audioEngine.delegate = self
        windowManager.loadDefaultSkin()
        windowManager.showMainWindow()
        windowManager.showEqualizer()
        windowManager.showPlaylist()
        windowManager.snapToDefaultPositions()

        let files = CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !files.isEmpty {
            windowManager.audioEngine.loadFiles(files)
            windowManager.audioEngine.play()
        }
    }

    // MARK: AudioEngineDelegate (as upstream's AppDelegate, classic windows only)

    func audioEngineDidChangeState(_ state: PlaybackState) {
        windowManager.mainWindowController?.updatePlaybackState()
    }

    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        windowManager.mainWindowController?.updateTime(current: current, duration: duration)
    }

    func audioEngineDidChangeTrack(_ track: Track?) {
        windowManager.mainWindowController?.updateTrackInfo(track)
    }

    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        windowManager.mainWindowController?.updateSpectrum(levels)
    }

    func audioEngineDidChangePlaylist() {
        windowManager.playlistWindowController?.reloadPlaylist()
    }

    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        NSLog("AppDelegate: Failed to load track '%@': %@", track.title, error.localizedDescription)
    }
}
