// Linux: UTType as file-extension sets, which is all a GTK file dialog filters on.
@_exported import Foundation

public struct UTType: Hashable, Sendable, CustomStringConvertible {
    public let identifier: String
    /// Extensions this type covers; categories (audio, movie) cover many.
    public let filenameExtensions: [String]

    public init(_ identifier: String, extensions: [String]) {
        self.identifier = identifier
        filenameExtensions = extensions
    }

    public init?(filenameExtension ext: String, conformingTo supertype: UTType? = nil) {
        let lower = ext.lowercased()
        guard !lower.isEmpty else { return nil }
        self.init("public.\(lower)", extensions: [lower])
    }

    public init?(_ identifier: String) {
        guard let known = UTType.known.first(where: { $0.identifier == identifier }) else { return nil }
        self = known
    }

    public var preferredFilenameExtension: String? { filenameExtensions.first }
    public var description: String { identifier }

    public func conforms(to type: UTType) -> Bool {
        type == self || Set(filenameExtensions).isSubset(of: Set(type.filenameExtensions))
    }

    public static let audio = UTType("public.audio", extensions: ["mp3", "flac", "m4a", "aac", "wav", "aiff", "aif", "ogg",
                                                                   "opus", "wma", "ape", "wv", "alac", "mpc", "cue"])
    public static let movie = UTType("public.movie", extensions: ["mkv", "mp4", "m4v", "mov", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "ts"])
    public static let video = movie
    public static let audiovisualContent = UTType("public.audiovisual-content", extensions: audio.filenameExtensions + movie.filenameExtensions)
    public static let mp3 = UTType("public.mp3", extensions: ["mp3"])
    public static let wav = UTType("com.microsoft.waveform-audio", extensions: ["wav"])
    public static let aiff = UTType("public.aiff-audio", extensions: ["aiff", "aif"])
    public static let mpeg4Audio = UTType("public.mpeg-4-audio", extensions: ["m4a"])
    public static let plainText = UTType("public.plain-text", extensions: ["txt"])
    public static let json = UTType("public.json", extensions: ["json"])
    public static let xml = UTType("public.xml", extensions: ["xml"])
    public static let png = UTType("public.png", extensions: ["png"])
    public static let jpeg = UTType("public.jpeg", extensions: ["jpg", "jpeg"])
    public static let image = UTType("public.image", extensions: ["png", "jpg", "jpeg", "bmp", "gif", "webp"])
    public static let zip = UTType("public.zip-archive", extensions: ["zip"])
    public static let folder = UTType("public.folder", extensions: [])
    public static let directory = folder
    public static let data = UTType("public.data", extensions: [])
    public static let item = UTType("public.item", extensions: [])
    public static let fileURL = UTType("public.file-url", extensions: [])
    public static let playlist = UTType("public.m3u-playlist", extensions: ["m3u", "m3u8", "pls"])
    public static let m3uPlaylist = UTType("public.m3u-playlist", extensions: ["m3u", "m3u8"])

    private static let known: [UTType] = [audio, movie, mp3, wav, aiff, mpeg4Audio, plainText, json, xml, png, jpeg, image, zip,
                                          folder, data, item, fileURL, m3uPlaylist]
}
