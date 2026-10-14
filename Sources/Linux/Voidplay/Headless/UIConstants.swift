import Foundation
import NullPlayerCore

// Temp-file prefixes owned by UI types the headless build leaves out. StreamRipper's
// launch-time sweep names them; the GTK stage brings the real types and deletes these.
/// ponytail: no waveform decoding on Linux yet (upstream's service decodes through AVFoundation);
/// a `.wal` seeker waveform shows as unsupported.
final class WaveformCacheService: @unchecked Sendable {
    static let prerenderTempPrefix = "waveform-prerender-"
    static let shared = WaveformCacheService()
    func loadSnapshot(for track: Track?, forceRegeneration: Bool = false) async -> WaveformSnapshot {
        .unsupported("Waveforms are not available on Linux yet")
    }
}
enum ModernSkinLoader { static let temporaryDirectoryPrefix = "ModernSkin_" }
