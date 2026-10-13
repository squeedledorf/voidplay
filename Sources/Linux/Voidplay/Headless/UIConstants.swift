import Foundation

// Temp-file prefixes owned by UI types the headless build leaves out. StreamRipper's
// launch-time sweep names them; the GTK stage brings the real types and deletes these.
enum WaveformCacheService { static let prerenderTempPrefix = "waveform-prerender-" }
enum ModernSkinLoader { static let temporaryDirectoryPrefix = "ModernSkin_" }
enum SkinLoader { static let temporaryDirectoryPrefix = "ClassicSkin_" }
