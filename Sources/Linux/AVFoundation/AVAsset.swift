import Foundation
import CFFmpeg

// MARK: - libavformat probe

/// What libavformat reports about a local file: container tags, streams, duration, cover art.
struct MediaProbe {
    struct AudioStream {
        let sampleRate: Int
        let channels: Int
    }

    let formatName: String
    /// Container tags followed by the first audio stream's (Ogg keeps Vorbis comments on the stream).
    let tags: [(key: String, value: String)]
    let audioStreams: [AudioStream]
    let hasVideo: Bool
    let duration: TimeInterval?
    let artwork: Data?

    private static let quiet: Void = av_log_set_level(-8)  // AV_LOG_QUIET

    init(url: URL) throws {
        _ = Self.quiet
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        var context: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&context, url.path, nil, nil) == 0, let ctx = context else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        defer { avformat_close_input(&context) }
        _ = avformat_find_stream_info(ctx, nil)

        formatName = ctx.pointee.iformat.map { String(cString: $0.pointee.name) } ?? ""
        var tags = Self.entries(ctx.pointee.metadata)
        var audio: [AudioStream] = []
        var video = false
        var art: Data?
        for i in 0..<Int(ctx.pointee.nb_streams) {
            guard let stream = ctx.pointee.streams[i], let par = stream.pointee.codecpar else { continue }
            if stream.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC != 0 {
                let packet = stream.pointee.attached_pic
                if art == nil, let data = packet.data, packet.size > 0 {
                    art = Data(bytes: data, count: Int(packet.size))
                }
                continue
            }
            switch par.pointee.codec_type {
            case AVMEDIA_TYPE_AUDIO:
                if audio.isEmpty { tags += Self.entries(stream.pointee.metadata) }
                audio.append(AudioStream(sampleRate: Int(par.pointee.sample_rate),
                                         channels: Int(par.pointee.ch_layout.nb_channels)))
            case AVMEDIA_TYPE_VIDEO:
                video = true
            default:
                break
            }
        }
        self.tags = tags
        audioStreams = audio
        hasVideo = video
        artwork = art
        let raw = ctx.pointee.duration
        duration = raw > 0 && raw != Int64.min ? Double(raw) / Double(AV_TIME_BASE) : nil
    }

    private static func entries(_ dict: OpaquePointer?) -> [(key: String, value: String)] {
        var out: [(key: String, value: String)] = []
        var entry: UnsafePointer<AVDictionaryEntry>?
        while let next = av_dict_iterate(dict, entry) {
            out.append((String(cString: next.pointee.key), String(cString: next.pointee.value)))
            entry = next
        }
        return out
    }
}

// MARK: - Metadata types

public struct AVMediaType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let audio = AVMediaType("soun")
    public static let video = AVMediaType("vide")
}

public struct AVMetadataFormat: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let id3Metadata = AVMetadataFormat("org.id3")
    public static let iTunesMetadata = AVMetadataFormat("com.apple.itunes")
    public static let quickTimeMetadata = AVMetadataFormat("com.apple.quicktime.mdta")
    /// No Apple constant exists; FLAC/Ogg tags surface under this key space.
    public static let vorbisComment = AVMetadataFormat("org.xiph.vorbis-comment")
}

public struct AVMetadataKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let commonKeyTitle = AVMetadataKey("title")
    public static let commonKeyArtist = AVMetadataKey("artist")
    public static let commonKeyAlbumName = AVMetadataKey("albumName")
    public static let commonKeyCreationDate = AVMetadataKey("creationDate")
    public static let commonKeyArtwork = AVMetadataKey("artwork")
    public static let commonKeyType = AVMetadataKey("type")
    public static let commonKeyCopyrights = AVMetadataKey("copyrights")
    public static let commonKeyCreator = AVMetadataKey("creator")
    public static let commonKeyDescription = AVMetadataKey("description")
}

public struct AVMetadataIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public final class AVMetadataItem: @unchecked Sendable {
    public let key: Any?
    public let keySpace: AVMetadataFormat
    public let identifier: AVMetadataIdentifier?
    public let commonKey: AVMetadataKey?
    public let value: Any?

    init(format: AVMetadataFormat, key: String, commonKey: AVMetadataKey?, value: Any) {
        self.key = key
        self.keySpace = format
        self.identifier = AVMetadataIdentifier(rawValue: "\(format.rawValue)/\(key)")
        self.commonKey = commonKey
        self.value = value
    }

    public var stringValue: String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    public var numberValue: NSNumber? {
        switch value {
        case let number as NSNumber: return number
        case let string as String:
            let digits = string.prefix { $0.isNumber }
            return Int(digits).map { NSNumber(value: $0) }
        default: return nil
        }
    }

    public var dataValue: Data? { value as? Data }
}

// MARK: - Asset

public class AVAssetTrack {
    public let mediaType: AVMediaType
    public let formatDescriptions: [Any]

    init(mediaType: AVMediaType, formatDescriptions: [Any]) {
        self.mediaType = mediaType
        self.formatDescriptions = formatDescriptions
    }
}

public class AVAsset: @unchecked Sendable {
    public let url: URL
    private let probe: MediaProbe?

    public init(url: URL) {
        self.url = url
        probe = try? MediaProbe(url: url)
    }

    public var duration: CMTime {
        guard let seconds = probe?.duration else { return .invalid }
        return CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
    }

    public var availableMetadataFormats: [AVMetadataFormat] {
        metadata.isEmpty ? [] : [metadataFormat]
    }

    public func metadata(forFormat format: AVMetadataFormat) -> [AVMetadataItem] {
        format == metadataFormat ? metadata : []
    }

    public var commonMetadata: [AVMetadataItem] { metadata.filter { $0.commonKey != nil } }

    public private(set) lazy var metadata: [AVMetadataItem] = makeMetadata()

    public func tracks(withMediaType mediaType: AVMediaType) -> [AVAssetTrack] {
        guard let probe else { return [] }
        switch mediaType {
        case .audio:
            return probe.audioStreams.map {
                AVAssetTrack(mediaType: .audio, formatDescriptions: [
                    CMFormatDescription(sampleRate: Double($0.sampleRate), channels: UInt32($0.channels)),
                ])
            }
        case .video:
            return probe.hasVideo ? [AVAssetTrack(mediaType: .video, formatDescriptions: [])] : []
        default:
            return []
        }
    }

    // MARK: Async loading

    public func load<T>(_ property: AVAsyncProperty<AVAsset, T>) async throws -> T {
        property.get(self)
    }

    public func loadMetadata(for format: AVMetadataFormat) async throws -> [AVMetadataItem] {
        metadata(forFormat: format)
    }

    public func loadTracks(withMediaType mediaType: AVMediaType) async throws -> [AVAssetTrack] {
        tracks(withMediaType: mediaType)
    }

    // MARK: Tag mapping

    /// The key space AVFoundation would put this container's tags in.
    private var metadataFormat: AVMetadataFormat {
        let name = probe?.formatName ?? ""
        if name.contains("mp3") || name.contains("aiff") || name.contains("wav") { return .id3Metadata }
        if name.contains("mp4") || name.contains("mov") { return .iTunesMetadata }
        return .vorbisComment
    }

    private func makeMetadata() -> [AVMetadataItem] {
        guard let probe else { return [] }
        let format = metadataFormat
        var items = probe.tags.map { tag -> AVMetadataItem in
            let generic = tag.key.lowercased()
            return AVMetadataItem(format: format,
                                  key: Self.nativeKey(generic, original: tag.key, format: format),
                                  commonKey: Self.commonKeys[generic],
                                  value: tag.value)
        }
        if let art = probe.artwork {
            let key = format == .id3Metadata ? "APIC" : format == .iTunesMetadata ? "covr" : "METADATA_BLOCK_PICTURE"
            items.append(AVMetadataItem(format: format, key: key, commonKey: .commonKeyArtwork, value: art))
        }
        return items
    }

    private static let commonKeys: [String: AVMetadataKey] = [
        "title": .commonKeyTitle,
        "artist": .commonKeyArtist,
        "album": .commonKeyAlbumName,
        "date": .commonKeyCreationDate,
        "year": .commonKeyCreationDate,
        "copyright": .commonKeyCopyrights,
    ]

    /// libavformat normalises tags to generic names; map them back to the native key each
    /// container uses, which is what AVFoundation exposes as `item.key`.
    private static let id3Keys = [
        "title": "TIT2", "artist": "TPE1", "album": "TALB", "album_artist": "TPE2", "genre": "TCON",
        "composer": "TCOM", "track": "TRCK", "disc": "TPOS", "date": "TDRC", "comment": "COMM",
        "copyright": "TCOP", "grouping": "TIT1", "publisher": "TPUB", "language": "TLAN",
    ]
    private static let iTunesKeys = [
        "title": "©nam", "artist": "©ART", "album": "©alb", "album_artist": "aART", "genre": "©gen",
        "composer": "©wrt", "track": "trkn", "disc": "disk", "date": "©day", "comment": "©cmt",
        "copyright": "cprt", "grouping": "©grp", "show": "tvsh", "season_number": "tvsn",
        "episode_sort": "tves", "episode_id": "tven",
    ]
    private static let vorbisKeys = [
        "album_artist": "ALBUMARTIST", "track": "TRACKNUMBER", "disc": "DISCNUMBER",
    ]

    private static func nativeKey(_ generic: String, original: String, format: AVMetadataFormat) -> String {
        switch format {
        case .id3Metadata: return id3Keys[generic] ?? original.uppercased()
        case .iTunesMetadata: return iTunesKeys[generic] ?? original
        default: return vorbisKeys[generic] ?? original.uppercased()
        }
    }
}

public final class AVURLAsset: AVAsset, @unchecked Sendable {
    public init(url: URL, options: [String: Any]? = nil) {
        super.init(url: url)
    }
}

// MARK: - Async properties

public class AVPartialAsyncProperty<Root> {}

public final class AVAsyncProperty<Root, Value>: AVPartialAsyncProperty<Root> {
    let get: (Root) -> Value
    init(_ get: @escaping (Root) -> Value) { self.get = get }
}

extension AVPartialAsyncProperty where Root == AVAsset {
    public static var metadata: AVAsyncProperty<AVAsset, [AVMetadataItem]> { .init { $0.metadata } }
    public static var commonMetadata: AVAsyncProperty<AVAsset, [AVMetadataItem]> { .init { $0.commonMetadata } }
    public static var duration: AVAsyncProperty<AVAsset, CMTime> { .init { $0.duration } }
    public static var availableMetadataFormats: AVAsyncProperty<AVAsset, [AVMetadataFormat]> {
        .init { $0.availableMetadataFormats }
    }
}

extension AVPartialAsyncProperty where Root == AVMetadataItem {
    public static var dataValue: AVAsyncProperty<AVMetadataItem, Data?> { .init { $0.dataValue } }
    public static var stringValue: AVAsyncProperty<AVMetadataItem, String?> { .init { $0.stringValue } }
    public static var numberValue: AVAsyncProperty<AVMetadataItem, NSNumber?> { .init { $0.numberValue } }
}

extension AVMetadataItem {
    public func load<T>(_ property: AVAsyncProperty<AVMetadataItem, T>) async throws -> T {
        property.get(self)
    }
}
