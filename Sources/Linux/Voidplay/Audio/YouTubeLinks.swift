import Foundation
import NullPlayerCore

/// YouTube links as playlist entries: a playlist link becomes one track per video, a video link
/// one track, each titled and timed from `yt-dlp --flat-playlist -J`. mpv streams the audio
/// through yt-dlp when the track plays (see `AudioEngine.mpvTarget`); nothing is downloaded.
enum YouTubeLinks {
    static func isYouTube(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    enum Failure: LocalizedError {
        case noYtDlp, ytDlp(String)
        var errorDescription: String? {
            switch self {
            case .noYtDlp: return "yt-dlp is not installed."
            case .ytDlp(let message): return message
            }
        }
    }

    /// The link's videos in playlist order; private and deleted entries are left out.
    static func tracks(for url: URL) async throws -> [Track] {
        guard let ytDlp = StreamRipper.resolveYtDlp() else { throw Failure.noYtDlp }
        let json = try await Task.detached(priority: .userInitiated) {
            try run(ytDlp, ["--flat-playlist", "--dump-single-json", "--no-warnings", url.absoluteString])
        }.value
        guard let info = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        let entries = (info["entries"] as? [[String: Any]]) ?? [info]
        return entries.compactMap(track)
    }

    static func track(_ entry: [String: Any]) -> Track? {
        guard let id = entry["id"] as? String, let title = entry["title"] as? String,
              !["[Private video]", "[Deleted video]"].contains(title),
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return nil }
        let artist = (entry["channel"] as? String) ?? (entry["uploader"] as? String)
        return Track(url: url, title: title, artist: artist, duration: entry["duration"] as? TimeInterval)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()  // before waiting: a full pipe would block yt-dlp
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.ytDlp(text.isEmpty ? "yt-dlp failed (\(process.terminationStatus))." : text)
        }
        return data
    }
}
