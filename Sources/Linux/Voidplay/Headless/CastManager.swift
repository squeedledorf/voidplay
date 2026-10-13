import Foundation
import NullPlayerCore

/// Linux placeholder for upstream's CastManager. Discovery finds nothing and every cast throws,
/// so the CLI reports casting as unavailable instead of failing to build.
/// ponytail: Sonos/Chromecast/DLNA need a Network.framework replacement (mDNS, TLS sockets,
/// SSDP); that is the casting stage, which swaps this file for upstream's Casting/ sources.
final class CastManager {
    static let shared = CastManager()
    static weak var cliAudioEngine: AudioEngine?
    static let sessionDidChangeNotification = Notification.Name("CastSessionDidChange")
    static let playbackStateDidChangeNotification = Notification.Name("CastPlaybackStateDidChange")
    static let trackChangeLoadingNotification = Notification.Name("CastTrackChangeLoading")

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Casting is not available in the Linux build yet." }
    }

    static var currentPlaybackDeviceName: String { AudioOutputManager.shared.currentDeviceDisplayName }

    private(set) var discoveredDevices: [CastDevice] = []
    var isCasting: Bool { false }
    var isVideoCastPlaying: Bool { false }
    var currentCast: CurrentCast { .none }
    var videoCastCurrentTime: TimeInterval { 0 }
    var videoCastDuration: TimeInterval { 0 }

    func startDiscovery() {}
    func stopCasting() async {}
    func pause() async throws { throw Unavailable() }
    func resume() async throws { throw Unavailable() }
    func seek(to time: TimeInterval) async throws { throw Unavailable() }
    func castCurrentTrack(to device: CastDevice) async throws { throw Unavailable() }
    func joinSonosToGroup(zoneUDN: String, coordinatorUDN: String) async throws { throw Unavailable() }
    func castLocalVideo(_ url: URL, title: String, to device: CastDevice) async throws { throw Unavailable() }
    func castPlexMovie(_ movie: PlexMovie, to device: CastDevice) async throws { throw Unavailable() }
    func castPlexEpisode(_ episode: PlexEpisode, to device: CastDevice) async throws { throw Unavailable() }
    func castJellyfinMovie(_ movie: JellyfinMovie, to device: CastDevice) async throws { throw Unavailable() }
    func castJellyfinEpisode(_ episode: JellyfinEpisode, to device: CastDevice) async throws { throw Unavailable() }
    func castEmbyMovie(_ movie: EmbyMovie, to device: CastDevice) async throws { throw Unavailable() }
    func castEmbyEpisode(_ episode: EmbyEpisode, to device: CastDevice) async throws { throw Unavailable() }

    // Pure helpers, same as upstream's.
    static func detectAudioContentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "flac": return "audio/flac"
        case "m4a", "aac", "alac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "ogg": return "audio/ogg"
        case "opus": return "audio/opus"
        case "wma": return "audio/x-ms-wma"
        default: return "audio/mpeg"
        }
    }

    static func detectAudioContentType(for url: URL) -> String {
        detectAudioContentType(forExtension: url.pathExtension)
    }
}

enum ChromecastManager {
    static let mediaStatusDidUpdateNotification = Notification.Name("ChromecastMediaStatusDidUpdate")
}

struct CastMediaStatus {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval?
    var playerState: CastPlayerState = .unknown
    var mediaSessionId: Int = 0
}

enum CastPlayerState: String {
    case idle = "IDLE"
    case buffering = "BUFFERING"
    case playing = "PLAYING"
    case paused = "PAUSED"
    case unknown = "UNKNOWN"
}

/// Port of upstream's local HTTP server, which also serves the play-history pages.
/// ponytail: only the port constant until the casting stage brings the server itself.
enum LocalMediaServer {
    static let httpPort: UInt16 = 8765
}
