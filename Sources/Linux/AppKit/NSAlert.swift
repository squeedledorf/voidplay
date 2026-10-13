import Foundation

/// Headless alert: reports to stderr and answers `.cancel`, so no question a backend asks
/// can be confirmed without a person. The GTK stage gives these a real dialog.
public final class NSAlert {
    public enum Style { case warning, informational, critical }

    public var messageText = ""
    public var informativeText = ""
    public var alertStyle: Style = .warning

    public init() {}

    public func addButton(withTitle title: String) {}

    @discardableResult
    public func runModal() -> NSApplication.ModalResponse {
        let detail = informativeText.isEmpty ? "" : ": \(informativeText)"
        FileHandle.standardError.write(Data("\(messageText)\(detail)\n".utf8))
        return .cancel
    }
}
