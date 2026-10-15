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

/// Tripex's core decodes its embedded JPEG textures through macOS ImageIO (C++, upstream_port/):
/// until that has a Linux decoder the engine reports itself unavailable and the GL view falls back
/// to black. Members are the ones the GL view and menus name, with upstream's defaults keys.
final class TripexEngine: VisualizationEngine {
    enum DefaultsKey {
        static let lastEffectIndex   = "tripex.lastEffectIndex"
        static let lockedEffectIndex = "tripex.lockedEffectIndex"
        static let intensityScale    = "tripex.intensityScale"
        static let cycleMode         = "tripex.cycleMode"
        static let cycleInterval     = "tripex.cycleInterval"
    }
    init(width: Int, height: Int) {}
    var isAvailable: Bool { false }
    var displayName: String { "Tripex" }
    func setViewportSize(width: Int, height: Int) {}
    func addPCMMono(_ samples: [Float]) {}
    func renderFrame() {}
    func cleanup() {}
    var effectCount: Int { 0 }
    var currentEffectIndex: Int { -1 }
    var isHolding: Bool { false }
    var intensityScale: Float = 1
    func effectName(at index: Int) -> String { "" }
    func nextEffect() {}
    func previousEffect() {}
    func randomEffect() {}
    func selectEffect(at index: Int) {}
    func reconfigure() {}
    func toggleHold() {}
    func setHold(_ on: Bool) {}
    func toggleAudioInfo() {}
    func toggleHelp() {}
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
