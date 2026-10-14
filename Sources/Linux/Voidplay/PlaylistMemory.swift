import Foundation
import NullPlayerCore

/// The playlist as it was when Voidplay last closed: saved whenever it or the current track
/// changes, restored at launch (not playing), as upstream's AppStateManager does on macOS.
///
/// ponytail: the playlist and current track only, not the playback position or server-backed
/// track ids (Plex/Jellyfin…); upstream's full state restore replaces this once it runs on Linux.
enum PlaylistMemory {
    private struct Saved: Codable {
        struct Entry: Codable {
            let url: String
            let title: String
            let artist: String?
            let album: String?
            let duration: Double?
        }
        var entries: [Entry]
        var currentIndex: Int
    }

    private static var fileURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        return base.appendingPathComponent(ClientIdentity.dataDirectoryName).appendingPathComponent("playlist.json")
    }

    private static var pendingSave: DispatchWorkItem?

    /// Saves shortly after the last change (a burst of edits writes once).
    static func scheduleSave(_ engine: AudioEngine) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { save(engine) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    static func save(_ engine: AudioEngine) {
        pendingSave?.cancel()
        pendingSave = nil
        let saved = Saved(entries: engine.playlist.map {
            .init(url: $0.url.absoluteString, title: $0.title, artist: $0.artist, album: $0.album, duration: $0.duration)
        }, currentIndex: engine.currentIndex)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("PlaylistMemory: could not save: %@", error.localizedDescription)
        }
    }

    /// Restores the saved playlist (skipping local files that are gone); false when there is none.
    @discardableResult
    static func restore(into engine: AudioEngine) -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return false }
        var tracks: [Track] = []
        var current = -1
        for (index, entry) in saved.entries.enumerated() {
            guard let url = URL(string: entry.url),
                  !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else { continue }
            if index == saved.currentIndex { current = tracks.count }
            tracks.append(Track(url: url, title: entry.title, artist: entry.artist, album: entry.album,
                                duration: entry.duration))
        }
        guard !tracks.isEmpty else { return false }
        engine.restorePlaylist(tracks, currentIndex: current)
        return true
    }
}
