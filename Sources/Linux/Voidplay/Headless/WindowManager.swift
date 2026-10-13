import Foundation

/// Headless stand-in for upstream's WindowManager: owns the shared AudioEngine and answers the
/// video and window questions the backends ask with "no window". The GTK stage replaces it.
final class WindowManager {
    static let shared = WindowManager()

    lazy var audioEngine = AudioEngine()

    var isVideoContentActive: Bool { false }
    var isVideoActivePlayback: Bool { false }
    var isVideoCastingActive: Bool { false }

    func setVideoVolume(_ volume: Float) {}
    func stopVideo() {}
}
