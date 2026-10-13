import Foundation

public enum NSApplication {
    public struct ModalResponse: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let OK = ModalResponse(rawValue: 1)
        public static let cancel = ModalResponse(rawValue: 0)
        public static let alertFirstButtonReturn = ModalResponse(rawValue: 1000)
        public static let alertSecondButtonReturn = ModalResponse(rawValue: 1001)
        public static let alertThirdButtonReturn = ModalResponse(rawValue: 1002)
    }
}

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
