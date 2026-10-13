import Foundation
import AppKit

// MediaPlayer stand-in: the Now Playing info and remote commands upstream's NowPlayingManager
// uses, published to the desktop over MPRIS (MPRIS.swift) instead of Control Center.

public let MPMediaItemPropertyTitle = "title"
public let MPMediaItemPropertyArtist = "artist"
public let MPMediaItemPropertyAlbumTitle = "albumTitle"
public let MPMediaItemPropertyPlaybackDuration = "playbackDuration"
public let MPMediaItemPropertyArtwork = "artwork"
public let MPNowPlayingInfoPropertyElapsedPlaybackTime = "MPNowPlayingInfoPropertyElapsedPlaybackTime"
public let MPNowPlayingInfoPropertyPlaybackRate = "MPNowPlayingInfoPropertyPlaybackRate"
public let MPNowPlayingInfoPropertyDefaultPlaybackRate = "MPNowPlayingInfoPropertyDefaultPlaybackRate"
public let MPNowPlayingInfoPropertyMediaType = "MPNowPlayingInfoPropertyMediaType"

public enum MPNowPlayingPlaybackState: UInt, Sendable { case unknown, playing, paused, stopped, interrupted }
public enum MPNowPlayingInfoMediaType: UInt, Sendable { case none, audio, video }

public final class MPNowPlayingInfoCenter {
    nonisolated(unsafe) private static let shared = MPNowPlayingInfoCenter()
    public static func `default`() -> MPNowPlayingInfoCenter { shared }

    public var nowPlayingInfo: [String: Any]? {
        didSet {
            infoDate = Date()
            MPRISServer.shared.nowPlayingDidChange()
        }
    }
    public var playbackState: MPNowPlayingPlaybackState = .unknown {
        didSet { MPRISServer.shared.nowPlayingDidChange() }
    }
    /// When `nowPlayingInfo` was last set: elapsed time runs on from there while playing.
    private(set) var infoDate = Date()

    /// Elapsed seconds now, extrapolated as Control Center does.
    var currentElapsed: TimeInterval {
        let elapsed = (nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        let rate = (nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
        return elapsed + (playbackState == .playing ? rate * Date().timeIntervalSince(infoDate) : 0)
    }
}

public final class MPMediaItemArtwork {
    public let bounds: CGRect
    private let requestHandler: (CGSize) -> NSImage
    public init(boundsSize: CGSize, requestHandler: @escaping (CGSize) -> NSImage) {
        bounds = CGRect(origin: .zero, size: boundsSize)
        self.requestHandler = requestHandler
    }
    public func image(at size: CGSize) -> NSImage? { requestHandler(size) }
}

public enum MPRemoteCommandHandlerStatus: Int, Sendable {
    case success, noSuchContent, noActionableNowPlayingItem, deviceNotFound, commandFailed = 200
}

public class MPRemoteCommandEvent {
    public let command: MPRemoteCommand
    public let timestamp = ProcessInfo.processInfo.systemUptime
    init(command: MPRemoteCommand) { self.command = command }
}

public final class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent {
    public let positionTime: TimeInterval
    init(command: MPRemoteCommand, positionTime: TimeInterval) {
        self.positionTime = positionTime
        super.init(command: command)
    }
}

public class MPRemoteCommand {
    public var isEnabled = false
    private var handlers: [(id: UUID, handler: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)] = []

    @discardableResult
    public func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        let id = UUID()
        handlers.append((id, handler))
        return id
    }
    public func removeTarget(_ target: Any?) {
        if let id = target as? UUID { handlers.removeAll { $0.id == id } } else if target == nil { handlers.removeAll() }
    }

    var isAvailable: Bool { isEnabled && !handlers.isEmpty }

    @discardableResult
    func send(_ event: MPRemoteCommandEvent? = nil) -> Bool {
        guard isEnabled else { return false }
        let event = event ?? MPRemoteCommandEvent(command: self)
        return handlers.contains { $0.handler(event) == .success }
    }
}

public final class MPRemoteCommandCenter {
    nonisolated(unsafe) private static let instance = MPRemoteCommandCenter()
    /// Asking for the command centre is what puts the player on the bus, as registering for remote
    /// commands is what makes a macOS app show up in Control Center.
    public static func shared() -> MPRemoteCommandCenter {
        MPRISServer.shared.start()
        return instance
    }

    public let playCommand = MPRemoteCommand()
    public let pauseCommand = MPRemoteCommand()
    public let stopCommand = MPRemoteCommand()
    public let togglePlayPauseCommand = MPRemoteCommand()
    public let nextTrackCommand = MPRemoteCommand()
    public let previousTrackCommand = MPRemoteCommand()
    public let changePlaybackPositionCommand = MPRemoteCommand()

    static var current: MPRemoteCommandCenter { instance }
}
