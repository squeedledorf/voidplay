import AppKit
import NullPlayerCore

// Types from window families that are not on Linux yet, as far as the classic windows name them.
// Each goes when its real upstream file joins upstream-sources.txt.

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
    var contextMenu: NSMenu? { nil }
    func toggleFullScreen(_ sender: Any?) {}
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
    func updateSpectrum(_ data: [Float]) {}
    func setAudioActive(_ active: Bool) {}
    var isRendering: Bool { false }
    func resumeRenderingAfterWindowTransition() {}
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

// MARK: Winamp Modern (.wal) pieces not on Linux yet

/// The skin-settings and colour-theme dialogs (Auto Layout forms): later. Menu entries open nothing.
final class WinampModernSkinSettingsWindowController: NSWindowController {
    init(runtime: WinampModernScriptRuntime) { super.init(window: nil) }
    required init?(coder: NSCoder) { nil }
    func refreshValues() {}
}

final class WinampModernSkinColorsWindowController: NSWindowController {
    init(controller: WinampModernMainWindowController) { super.init(window: nil) }
    required init?(coder: NSCoder) { nil }
    func refreshValues() {}
}

/// A `.wal` skin's embedded web browser needs WebKitGTK: until then the box stays empty.
final class WinampModernBrowserSurfaceView: NSView, WinampModernBrowserSurface {
    init(frame frameRect: NSRect, vfs: Any?) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { nil }
    var view: NSView { self }
    func navigate(_ request: WinampModernBrowserRequest) {}
    func setVisible(_ visible: Bool) { isHidden = !visible }
    func setShowsLocationBar(_ shows: Bool) {}
    func applySkinScale(_ scale: CGFloat) {}
    func unmountFromHolder() { removeFromSuperview() }
    func prepareForUITeardown() {}
}

/// Windows a `.wal` skin can host that are not on Linux yet: empty panels of their usual size.
class NotYetPortedPanel: NSView, WinampModernHostedSurface {
    var view: NSView { self }
    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {}
    func applyPalette(_ style: WinampModernSurfaceStyle) {}
    func applySkinScale(_ scale: CGFloat) {}
    func resume() {}
    func suspend() {}
    func unmountFromHolder() { removeFromSuperview() }
    func prepareForUITeardown() {}
}
final class EqualizerStudioView: NotYetPortedPanel { static let designSize = NSSize(width: 480, height: 260) }
final class WaveformView: NotYetPortedPanel {}
final class SpectrumView: NotYetPortedPanel {}
final class SonosWindowView: NotYetPortedPanel {}
final class PeppyMeterView: NotYetPortedPanel {}
final class NetworkMonitorView: NotYetPortedPanel {}
final class ModernProjectMView: NotYetPortedPanel {}
final class CavaView: NotYetPortedPanel {}
final class AudioAnalysisView: NotYetPortedPanel {}
final class ArtWindowView: NotYetPortedPanel {}

final class PlexBrowserView: NotYetPortedPanel {
    init(embeddedFrame: NSRect, skinScale: @escaping () -> CGFloat, presentLinkSheet: @escaping () -> Void) {
        super.init(frame: embeddedFrame)
    }
    required init?(coder: NSCoder) { nil }
    var browseModeRawValue: Int = 0
    func showLinkSheetFromHost() {}
    func applyWinampModernStyle(_ style: WinampModernSurfaceStyle) {}
}

final class PlexLinkSheet {
    func showAsSheet(from window: NSWindow, completion: @escaping (Bool) -> Void) {}
}
