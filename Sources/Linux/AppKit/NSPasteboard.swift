import Foundation

/// Clipboard and drag data. Only the type names and URL reading exist so far.
/// ponytail: GdkClipboard copy/paste and GtkDropTarget file drops arrive with the views that use them.
open class NSPasteboard {
    public struct PasteboardType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let string = PasteboardType("public.utf8-plain-text")
        public static let fileURL = PasteboardType("public.file-url")
        public static let URL = PasteboardType("public.url")
        public static let png = PasteboardType("public.png")
        public static let tiff = PasteboardType("public.tiff")
    }

    public struct ReadingOptionKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let urlReadingFileURLsOnly = ReadingOptionKey(rawValue: "NSPasteboardURLReadingFileURLsOnlyKey")
    }

    public static let general = NSPasteboard()
    var urls: [URL] = []
    var strings: [PasteboardType: String] = [:]

    public init() {}

    public var types: [PasteboardType]? { Array(strings.keys) + (urls.isEmpty ? [] : [.fileURL]) }

    open func readObjects(forClasses classes: [AnyClass], options: [ReadingOptionKey: Any]?) -> [Any]? {
        urls.isEmpty ? nil : urls.map { $0 as NSURL }
    }

    @discardableResult open func clearContents() -> Int { urls = []; strings = [:]; return 0 }
    @discardableResult open func setString(_ string: String, forType type: PasteboardType) -> Bool { strings[type] = string; return true }
    open func string(forType type: PasteboardType) -> String? { strings[type] }
    @discardableResult open func writeObjects(_ objects: [Any]) -> Bool {
        urls += objects.compactMap { ($0 as? URL) ?? ($0 as? NSURL).map { $0 as URL } }
        return true
    }
}

public struct NSDragOperation: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let copy = NSDragOperation(rawValue: 1)
    public static let link = NSDragOperation(rawValue: 2)
    public static let generic = NSDragOperation(rawValue: 4)
    public static let move = NSDragOperation(rawValue: 16)
    public static let delete = NSDragOperation(rawValue: 32)
    public static let every = NSDragOperation(rawValue: .max)
}

public protocol NSDraggingInfo: AnyObject {
    var draggingPasteboard: NSPasteboard { get }
    var draggingLocation: NSPoint { get }
    var draggingSourceOperationMask: NSDragOperation { get }
    var draggingSource: Any? { get }
}
