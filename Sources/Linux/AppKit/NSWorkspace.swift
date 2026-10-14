import Foundation

/// Desktop integration through freedesktop tools: xdg-open, and the FileManager1 D-Bus
/// interface for "reveal in file manager".
public final class NSWorkspace: @unchecked Sendable {
    public static let shared = NSWorkspace()
    public static let volumeURLUserInfoKey = "NSWorkspaceVolumeURLKey"
    public static let didWakeNotification = Notification.Name("NSWorkspaceDidWakeNotification")

    /// Darwin posts mount/sleep notifications here; nothing posts them on Linux yet.
    public let notificationCenter = NotificationCenter()

    @discardableResult
    public func open(_ url: URL) -> Bool {
        Self.spawn(["xdg-open", url.isFileURL ? url.path : url.absoluteString])
    }

    public func activateFileViewerSelecting(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let items = "[" + urls.map { "'\($0.absoluteString)'" }.joined(separator: ",") + "]"
        let shown = Self.spawn(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
                                "--object-path", "/org/freedesktop/FileManager1",
                                "--method", "org.freedesktop.FileManager1.ShowItems", items, ""])
        if !shown { open(urls[0].deletingLastPathComponent()) }
    }

    @discardableResult
    public func selectFile(_ path: String?, inFileViewerRootedAtPath root: String) -> Bool {
        if let path {
            activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return true
        }
        return open(URL(fileURLWithPath: root))
    }

    /// Runs a helper detached from our stdio; true when it launched and exited cleanly.
    private static func spawn(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

extension FileManager {
    /// Moves the item to the freedesktop trash (`gio trash`), as Finder's Trash.
    /// ponytail: shells out to gio; reports no resulting URL.
    public func trashItem(at url: URL, resultingItemURL outResultingURL: UnsafeMutablePointer<NSURL?>?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gio")
        process.arguments = ["trash", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
