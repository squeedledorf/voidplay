import AppKit
import NullPlayerCore

// Types from window families that are not on Linux yet, as far as the classic windows name them.
// Each goes when its real upstream file joins upstream-sources.txt.

final class WinampModernMainWindowController: NSWindowController {
    var currentPalette: WasabiPalette? { nil }
}
final class AudionFaceMainWindowController: NSWindowController {}

/// The GPU spectrum overlay (Metal on macOS). Until the OpenGL/Vulkan port, no shader mode is
/// available, so the main window stays on its CPU-drawn spectrum.
final class SpectrumAnalyzerView: NSView {
    static func isShaderAvailable(for mode: SpectrumQualityMode) -> Bool { false }

    var isEmbedded = false
    var normalizationUserDefaultsKey = "spectrumNormalizationMode"
    var qualityMode: SpectrumQualityMode = .classic
    var decayMode: SpectrumDecayMode = .snappy
    var lightningStyle: LightningStyle = .classic
    var matrixColorScheme: MatrixColorScheme = .classic
    var matrixIntensity: MatrixIntensity = .subtle
    var flameStyle: FlameStyle = .inferno
    var flameIntensity: FlameIntensity = .mellow
    var ekgStyle: EKGStyle = .clinical
    func visClassicTransparentBackgroundEnabled() -> Bool { false }

    func refreshNormalizationMode() {}
    func updateSpectrum(_ levels: [Float]) {}
    func skinDidChange() {}
    func startDisplayLink() {}
    func stopDisplayLink() {}
    func loadNextVisClassicProfile() -> Bool { false }
    func loadPreviousVisClassicProfile() -> Bool { false }
    func setVisClassicTransparentBackground(_ enabled: Bool) -> Bool { false }
}

// MARK: Video and GL visualizers (later stages)

/// The video player window (libmpv video stage). Never instantiated yet; members answer idle.
final class VideoPlayerWindowController: NSWindowController {
    var hasVideoOutput: Bool { false }
    var presentationSize: CGSize { .zero }
    var currentTitle: String? { nil }
    var currentArtworkTrack: Track? { nil }
    var didReachEndOfMedia: Bool { false }
    var isPlaying: Bool { false }
    var isCastingVideo: Bool { false }
    var isVideoOutputHosted: Bool { false }
    var isVideoFullScreenTransition: Bool { false }
    var showsVideoControlBar = false
    var videoControlBarMinimumWidth: CGFloat { 0 }
    var videoOutputMenu: NSMenu? { nil }
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    var volume: Float = 1
    func togglePlayPause() {}
    func stop() {}
    func seek(to time: TimeInterval) {}
    func skipForward(_ seconds: TimeInterval = 10) {}
    func skipBackward(_ seconds: TimeInterval = 10) {}
    func configureWMPVideoOutput(imageRect: CGRect?, maintainAspectRatio: Bool = true) {}
    func enterFullScreenReclaimingOutput() {}
    func handleVideoKey(_ event: NSEvent) -> Bool { false }
    func hostOutputWindow(over host: NSView) {}
    func reclaimVideoOutput(reveal: Bool) {}
    func updateHostedOutputFrame(over host: NSView) {}
}

/// The OpenGL visualization view (projectM, Geiss, Tripex): the GL visualizer stage.
/// `init?` fails, so every host falls back to its non-GL visuals; members answer empty.
final class VisualizationGLView: NSView {
    init?(frame frameRect: NSRect, pixelFormat: Any?) { nil }
    required init?(coder: NSCoder) { nil }
    var currentEngineType: VisualizationType { .projectM }
    var isProjectMAvailable: Bool { false }
    var isLowPowerMode: Bool { true }
    var pcmGain: Float { 1 }
    var normalBeatSensitivity: Float { 1 }
    var presetCount: Int { 0 }
    var currentPresetIndex: Int { -1 }
    var currentPresetName: String { "" }
    func presetName(at index: Int) -> String { "" }
    func presetPath(at index: Int) -> String { "" }
    func selectPreset(at index: Int, hardCut: Bool = false) {}
    func nextPreset(hardCut: Bool = false) {}
    func previousPreset(hardCut: Bool = false) {}
    func randomPreset(hardCut: Bool = false) {}
    func setCurrentPresetAsDefault() {}
    func setPCMGain(_ gain: Float) {}
    func setNormalBeatSensitivity(_ sensitivity: Float) {}
    func toggleLowPowerMode() {}
    func switchEngine(to type: VisualizationType, forceReload: Bool = false, persistPreference: Bool = true) {}
    func renderOffscreenImage(pixelWidth: Int, pixelHeight: Int) -> CGImage? { nil }
    func updatePCM(_ data: [Float]) {}
    func stopRendering() {}
    var geissEffectCount: Int { 0 }
    var currentGeissEffectName: String { "" }
    func geissEffectName(at index: Int) -> String { "" }
    func selectGeissEffect(at index: Int) {}
    func nextGeissEffect() {}
    func previousGeissEffect() {}
    func randomGeissEffect() {}
    func randomizeGeissPalette() {}
    func getGeissConfig() -> GeissEngine.Config? { nil }
    func setGeissConfig(_ cfg: GeissEngine.Config) {}
    var tripexEffectCount: Int { 0 }
    var currentTripexEffectIndex: Int { -1 }
    var isTripexHolding: Bool { false }
    var tripexIntensityScale: Float = 1
    func tripexEffectName(at index: Int) -> String { "" }
    func selectTripexEffect(at index: Int) {}
    func nextTripexEffect() {}
    func previousTripexEffect() {}
    func randomTripexEffect() {}
    func reconfigureTripex() {}
    func toggleTripexAudioInfo() {}
    func toggleTripexHelp() {}
    func toggleTripexHold() {}
}

/// Geiss and Tripex render through OpenGL with their bundled C++ cores (Sources/CGeissCore,
/// Sources/CTripexCore): the GL visualizer stage. These carry only what settings code names.
enum GeissEngine {
    struct Config: Equatable {
        var sensitivity: Float
        var gamma: Int
        var beatDetection: Bool
        var syncColorToSound: Bool
        var slideShift: Bool
        var modeLocked: Bool
        var paletteLocked: Bool
        var autoSwitchSeconds: Int
        var visMode: Int
    }
}

enum TripexEngine {
    enum DefaultsKey {
        static let intensityScale = "tripexIntensityScale"
        static let cycleInterval = "tripexCycleInterval"
        static let cycleMode = "tripexCycleMode"
    }
}
