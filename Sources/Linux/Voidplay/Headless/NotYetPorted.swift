import AppKit
import NullPlayerCore

// Types from window families that are not on Linux yet, as far as the classic windows name them.
// Each goes when its real upstream file joins upstream-sources.txt.

final class WinampModernMainWindowController: NSWindowController {
    var currentPalette: WasabiPalette? { nil }
}
final class WMPMainWindowController: NSWindowController {}
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
