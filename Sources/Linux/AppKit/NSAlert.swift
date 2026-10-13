import Foundation

/// Headless alert: reports to stderr and answers `.cancel`, so no question a backend asks
/// can be confirmed without a person. The GTK stage gives these a real dialog.
@preconcurrency @MainActor
public final class NSAlert {
    public enum Style { case warning, informational, critical }

    public var messageText = ""
    public var informativeText = ""
    public var alertStyle: Style = .warning
    public var accessoryView: NSView?
    public var icon: NSImage?
    public var showsSuppressionButton = false
    public var window: NSWindow? { nil }

    public init() {}

    public func addButton(withTitle title: String) {}

    @discardableResult
    public func runModal() -> NSApplication.ModalResponse {
        let detail = informativeText.isEmpty ? "" : ": \(informativeText)"
        FileHandle.standardError.write(Data("\(messageText)\(detail)\n".utf8))
        return .cancel
    }
}
