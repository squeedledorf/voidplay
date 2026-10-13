import Foundation
import PackagePlugin

/// Feeds the upstream macOS sources listed in Sources/Linux/upstream-sources.txt through
/// voidplay-source-transform, so the Linux target compiles them without an Objective-C runtime.
@main
struct LinuxSources: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "voidplay-source-transform")
        let root = context.package.directoryURL
        let list = root.appending(path: "Sources/Linux/upstream-sources.txt")
        let entries = try String(contentsOf: list, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        // "path" or "path#L<first>-<last>" for a slice of a file.
        var files: [(url: URL, range: String?)] = []
        for raw in entries {
            let parts = raw.split(separator: "#", maxSplits: 1).map(String.init)
            let entry = parts[0]
            let range = parts.count > 1 ? String(parts[1].dropFirst()) : nil
            let url = root.appending(path: entry)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                Diagnostics.error("upstream-sources.txt: \(entry) does not exist")
                continue
            }
            if isDirectory.boolValue {
                let found = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
                    .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
                files += found.sorted { $0.path < $1.path }.map { ($0, nil) }
            } else {
                files.append((url, range))
            }
        }

        let outDir = context.pluginWorkDirectoryURL
        var commands: [Command] = []
        var ids: [String] = []
        for (file, range) in files {
            let relative = String(file.path.dropFirst(root.path.count + 1)) + (range.map { "#L\($0)" } ?? "")
            let id = String(relative.map { $0.isLetter || $0.isNumber ? $0 : "_" })
            ids.append(id)
            let output = outDir.appending(path: id + ".swift")
            commands.append(.buildCommand(displayName: "Linux-transform \(relative)", executable: tool.url,
                                          arguments: ["transform", file.path, output.path, id] + (range.map { [$0] } ?? []),
                                          inputFiles: [file, tool.url, list], outputFiles: [output]))
        }
        let registry = outDir.appending(path: "UpstreamSelectors.swift")
        commands.append(.buildCommand(displayName: "Upstream selector registry", executable: tool.url,
                                      arguments: ["registry", registry.path] + ids,
                                      inputFiles: [list, tool.url], outputFiles: [registry]))
        return commands
    }
}
