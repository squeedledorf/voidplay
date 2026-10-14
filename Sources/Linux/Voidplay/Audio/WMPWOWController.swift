import Foundation

/// Linux WMPWOWController: upstream's state and defaults keys (Audio/WMPWOWAudioUnit.swift), with
/// the effect done by mpv filters the engine adds (`filters`), not an AVAudioUnit.
final class WMPWOWController {
    /// Side gain at WOW 100 is `1 + maximumWidening` (upstream's value).
    static let maximumWidening = 1.4

    private enum Key {
        static let enabled = "srsEnabled", level = "srsWOWLevel"
        static let bassLevel = "srsTruBassLevel", speakerSize = "srsSpeakerSize"
    }

    private let defaults: UserDefaults?
    private let onChange: () -> Void
    private(set) var enabled = false
    private(set) var level: Double = 50
    private(set) var bassLevel: Double = 50
    private(set) var speakerSize: Int = 0

    init(defaults: UserDefaults? = nil, onChange: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.onChange = onChange
        guard let defaults else { return }
        enabled = defaults.bool(forKey: Key.enabled)
        if let value = defaults.object(forKey: Key.level) as? Double, value.isFinite { level = max(0, min(100, value)) }
        if let value = defaults.object(forKey: Key.bassLevel) as? Double, value.isFinite { bassLevel = max(0, min(100, value)) }
        if let value = defaults.object(forKey: Key.speakerSize) as? Int, (0...2).contains(value) { speakerSize = value }
    }

    func setEnabled(_ value: Bool) { enabled = value; defaults?.set(value, forKey: Key.enabled); onChange() }
    func setLevel(_ value: Double) { level = max(0, min(100, value)); defaults?.set(level, forKey: Key.level); onChange() }
    func setBassLevel(_ value: Double) { bassLevel = max(0, min(100, value)); defaults?.set(bassLevel, forKey: Key.bassLevel); onChange() }
    func setSpeakerSize(_ value: Int) { speakerSize = max(0, min(2, value)); defaults?.set(speakerSize, forKey: Key.speakerSize); onChange() }

    /// mpv audio filters for the current settings: stereo widening (WOW) and a bass shelf whose
    /// corner follows the speaker size (TruBass). Empty when off.
    /// ponytail: approximates SRS with FFmpeg's extrastereo and bass filters; tune by ear.
    var filters: [String] {
        guard enabled else { return [] }
        var result: [String] = []
        if level > 0 { result.append("lavfi=[extrastereo=m=\(1 + level / 100 * Self.maximumWidening):c=1]") }
        if bassLevel > 0 {
            let corner = [80, 110, 150][speakerSize]
            result.append("lavfi=[bass=g=\(bassLevel / 100 * 9):f=\(corner)]")
        }
        return result
    }
}
