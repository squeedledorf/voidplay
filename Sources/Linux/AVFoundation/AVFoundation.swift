// Linux stand-in for the slice of AVFoundation that Voidplay's portable sources use:
// asset metadata, duration and stream format (read through libavformat), plus the
// parameter-holder audio units the tuning and EQ controllers configure. Playback itself
// is libmpv's job in the Linux AudioEngine; nothing here renders audio.
@_exported import Foundation

// MARK: - Time

public struct CMTime: Sendable, Equatable {
    public var value: Int64
    public var timescale: Int32

    public init(value: Int64, timescale: Int32) {
        self.value = value
        self.timescale = timescale
    }

    public static let invalid = CMTime(value: 0, timescale: 0)
    public static let zero = CMTime(value: 0, timescale: 1)

    public var seconds: Double { timescale > 0 ? Double(value) / Double(timescale) : .nan }
}

public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }

public func CMTimeMakeWithSeconds(_ seconds: Double, preferredTimescale: Int32) -> CMTime {
    CMTime(value: Int64((seconds * Double(preferredTimescale)).rounded()), timescale: preferredTimescale)
}

// MARK: - Audio format

public typealias AVAudioFramePosition = Int64
public typealias AVAudioFrameCount = UInt32
public typealias AVAudioChannelCount = UInt32

public struct AudioStreamBasicDescription: Sendable {
    public var mSampleRate: Double = 0
    public var mFormatID: UInt32 = 0
    public var mFormatFlags: UInt32 = 0
    public var mBytesPerPacket: UInt32 = 0
    public var mFramesPerPacket: UInt32 = 0
    public var mBytesPerFrame: UInt32 = 0
    public var mChannelsPerFrame: UInt32 = 0
    public var mBitsPerChannel: UInt32 = 0
    public var mReserved: UInt32 = 0

    public init() {}
}

/// Format of an audio stream, as libavformat reports it.
public final class CMFormatDescription {
    let description: UnsafeMutablePointer<AudioStreamBasicDescription>

    init(sampleRate: Double, channels: UInt32) {
        description = .allocate(capacity: 1)
        description.initialize(to: AudioStreamBasicDescription())
        description.pointee.mSampleRate = sampleRate
        description.pointee.mChannelsPerFrame = channels
    }

    deinit {
        description.deinitialize(count: 1)
        description.deallocate()
    }
}

public typealias CMAudioFormatDescription = CMFormatDescription

public func CMAudioFormatDescriptionGetStreamBasicDescription(
    _ description: CMAudioFormatDescription
) -> UnsafePointer<AudioStreamBasicDescription>? {
    UnsafePointer(description.description)
}

public final class AVAudioFormat {
    public let sampleRate: Double
    public let channelCount: AVAudioChannelCount

    public init(standardFormatWithSampleRate sampleRate: Double, channels: AVAudioChannelCount) {
        self.sampleRate = sampleRate
        self.channelCount = channels
    }
}

/// Opens a file for its format and length. It does not decode samples.
public final class AVAudioFile {
    public let url: URL
    public let fileFormat: AVAudioFormat
    public var processingFormat: AVAudioFormat { fileFormat }
    /// Length in sample frames.
    public let length: AVAudioFramePosition

    public init(forReading fileURL: URL) throws {
        let probe = try MediaProbe(url: fileURL)
        guard let audio = probe.audioStreams.first, audio.sampleRate > 0 else {
            throw NSError(domain: "com.apple.coreaudio.avfaudio", code: 1_954_115_647,
                          userInfo: [NSLocalizedDescriptionKey: "The file has no decodable audio stream."])
        }
        url = fileURL
        fileFormat = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate),
                                   channels: AVAudioChannelCount(audio.channels))
        length = AVAudioFramePosition((probe.duration ?? 0) * Double(audio.sampleRate))
    }
}

// MARK: - Audio units (parameter holders)

/// Base of the effect units. On Linux these hold parameters only; the engine reads them into mpv's filter chain.
open class AVAudioNode {
    public init() {}
}

open class AVAudioUnit: AVAudioNode {}

open class AVAudioUnitEffect: AVAudioUnit {
    public var bypass = false
}

public final class AVAudioUnitTimePitch: AVAudioUnitEffect {
    /// Pitch shift in cents.
    public var pitch: Float = 0
    public var rate: Float = 1
    public var overlap: Float = 8
}
