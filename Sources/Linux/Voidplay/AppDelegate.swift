import AppKit
import NullPlayerCore

/// Linux application delegate for the classic window set: forwards engine events to the windows
/// as upstream's App/AppDelegate does, and opens files named on the command line.
final class AppDelegate: NSObject, NSApplicationDelegate, AudioEngineDelegate {
    private let windowManager = WindowManager.shared
    private var isShowingPlayFailureAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowManager.audioEngine.delegate = self
        // Main window always shows a mini spectrum overlay — register as permanent consumer
        windowManager.audioEngine.addSpectrumConsumer("mainWindowSpectrum")
        NowPlayingManager.shared.setup()
        windowManager.loadDefaultSkin()
        windowManager.showMainWindow()
        windowManager.showEqualizer()
        windowManager.showPlaylist()
        windowManager.snapToDefaultPositions()

        let files = CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("-") }
            .compactMap { argument -> URL? in
                if argument.hasPrefix("http://") || argument.hasPrefix("https://") { return URL(string: argument) }
                let file = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
                return FileManager.default.fileExists(atPath: file.path) ? file : nil
            }
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
        NowPlayingManager.shared.periodicTimeUpdate()  // keeps MPRIS Position honest after seeks
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
