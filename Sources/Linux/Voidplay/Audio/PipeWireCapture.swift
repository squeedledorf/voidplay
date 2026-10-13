import Foundation

/// What this process plays, read back from PipeWire: `pw-record` linked to our own mpv output
/// stream (found through our process id) delivers float stereo, handed on in 2048-frame blocks
/// on a background thread. mpv has no client API for decoded audio; this sees exactly what it
/// outputs, after EQ and volume.
///
/// ponytail: PipeWire only (pw-record, from pipewire's tools); a PulseAudio-only desktop gets no
/// visuals. A libpipewire stream in-process would drop the subprocess if that ever matters.
final class PipeWireCapture {
    static let blockFrames = 2048
    static let sampleRate = 48_000.0

    private let onBlock: (UnsafePointer<UnsafeMutablePointer<Float>>, Int, Double) -> Void
    private var process: Process?

    init(onBlock: @escaping (UnsafePointer<UnsafeMutablePointer<Float>>, Int, Double) -> Void) {
        self.onBlock = onBlock
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Starts capturing; false when our stream or pw-record is not there (yet).
    @discardableResult
    func start() -> Bool {
        guard !isRunning, let tool = Self.which("pw-record"), let serial = Self.ownOutputStreamSerial() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["--target", serial, "--format", "f32", "--rate", "\(Int(Self.sampleRate))",
                             "--channels", "2", "--latency", "20ms", "--raw",
                             // Only ever our own stream: never fall back to another source (a mic)
                             // or follow it elsewhere when it goes away.
                             "-P", "{ node.dont-fallback = true node.dont-reconnect = true node.passive = true }", "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        self.process = process
        let reader = output.fileHandleForReading
        let onBlock = self.onBlock
        Thread.detachNewThread {
            let frames = Self.blockFrames
            let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
            channels[0] = left
            channels[1] = right
            defer { left.deallocate(); right.deallocate(); channels.deallocate() }
            let blockBytes = frames * 2 * MemoryLayout<Float>.size
            var pending = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }  // pw-record exited
                pending.append(chunk)
                while pending.count >= blockBytes {
                    pending.withUnsafeBytes { raw in
                        let samples = raw.bindMemory(to: Float.self)
                        for i in 0..<frames {
                            left[i] = samples[2 * i]
                            right[i] = samples[2 * i + 1]
                        }
                    }
                    pending.removeFirst(blockBytes)
                    onBlock(channels, frames, Self.sampleRate)
                }
            }
        }
        return true
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// Our playback stream's node serial: the Stream/Output/Audio node whose client is this process.
    static func ownOutputStreamSerial() -> String? {
        guard let tool = which("pw-dump") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        func props(_ object: [String: Any]) -> [String: Any] {
            (object["info"] as? [String: Any])?["props"] as? [String: Any] ?? [:]
        }
        let pid = Int(getpid())
        let clients = Set(objects.compactMap { object -> Int? in
            let p = props(object)
            let processID = (p["application.process.id"] as? Int) ?? Int(p["application.process.id"] as? String ?? "")
            return processID == pid ? object["id"] as? Int : nil
        })
        let node = objects.first { object in
            let p = props(object)
            let client = (p["client.id"] as? Int) ?? Int(p["client.id"] as? String ?? "") ?? -1
            return clients.contains(client) && p["media.class"] as? String == "Stream/Output/Audio"
        }
        guard let node else { return nil }
        let serial = props(node)["object.serial"]
        return (serial as? Int).map(String.init) ?? serial as? String
    }

    private static func which(_ name: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin").split(separator: ":") + ["/usr/bin"]
        return paths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
