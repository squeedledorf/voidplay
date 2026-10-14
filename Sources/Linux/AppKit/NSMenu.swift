import Foundation

/// Menu model. Items carry title, state, key equivalent and a target/action pair (or a
/// submenu); `NSMenu.popUpContextMenu` presents it with GTK.
@preconcurrency @MainActor
open class NSMenu {
    open var title: String
    public private(set) var items: [NSMenuItem] = []
    open weak var delegate: NSMenuDelegate?
    open var autoenablesItems = true
    open var font: NSFont?
    open var minimumWidth: CGFloat = 0
    public internal(set) weak var supermenu: NSMenu?

    public init(title: String = "") { self.title = title }
    public convenience init() { self.init(title: "") }

    open var numberOfItems: Int { items.count }

    open func addItem(_ item: NSMenuItem) { insertItem(item, at: items.count) }

    @discardableResult
    open func addItem(withTitle title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }

    open func insertItem(_ item: NSMenuItem, at index: Int) {
        item.menu = self
        item.submenu?.supermenu = self
        items.insert(item, at: max(0, min(index, items.count)))
    }

    open func removeItem(_ item: NSMenuItem) { items.removeAll { $0 === item } }
    open func removeItem(at index: Int) { if items.indices.contains(index) { items.remove(at: index) } }
    open func removeAllItems() { items.removeAll() }
    open func item(at index: Int) -> NSMenuItem? { items.indices.contains(index) ? items[index] : nil }
    open func item(withTitle title: String) -> NSMenuItem? { items.first { $0.title == title } }
    open func item(withTag tag: Int) -> NSMenuItem? { items.first { $0.tag == tag } }
    open func index(of item: NSMenuItem) -> Int { items.firstIndex { $0 === item } ?? -1 }
    open func update() { delegate?.menuNeedsUpdate(self) }
    open func cancelTracking() { MenuPresenter.dismissAll() }

    @discardableResult
    open func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        guard let view else { return false }
        MenuPresenter.present(self, at: view.convert(location, to: nil), in: view.window)
        return true
    }

    public static func popUpContextMenu(_ menu: NSMenu, with event: NSEvent, for view: NSView) {
        MenuPresenter.present(menu, at: event.locationInWindow, in: event.window ?? view.window)
    }
}

public protocol NSMenuDelegate: AnyObject {
    func menuNeedsUpdate(_ menu: NSMenu)
    func menuWillOpen(_ menu: NSMenu)
    func menuDidClose(_ menu: NSMenu)
}

extension NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {}
    public func menuWillOpen(_ menu: NSMenu) {}
    public func menuDidClose(_ menu: NSMenu) {}
}

@preconcurrency @MainActor
open class NSMenuItem {
    public enum State: Int, Sendable { case off = 0, on = 1, mixed = -1 }
    public typealias ControlState = State

    open var title: String
    open var action: Selector?
    open weak var target: AnyObject?
    open var keyEquivalent: String
    open var keyEquivalentModifierMask: NSEvent.ModifierFlags = [.command]
    open var state: State = .off
    open var isEnabled = true
    open var isHidden = false
    open var tag = 0
    open var representedObject: Any?
    open var image: NSImage?
    open var indentationLevel = 0
    open var toolTip: String?
    open var attributedTitle: NSAttributedString?
    open var identifier: NSUserInterfaceItemIdentifier?
    open var isAlternate = false
    open var view: NSView?
    open var submenu: NSMenu? { didSet { submenu?.supermenu = menu } }
    public internal(set) weak var menu: NSMenu?
    public let isSeparatorItem: Bool
    open var hasSubmenu: Bool { submenu != nil }
    /// Linux addition: a closure action, for menus built in Swift-only code.
    open var handler: ((NSMenuItem) -> Void)?

    public init(title: String, action: Selector?, keyEquivalent: String) {
        self.title = title
        self.action = action
        self.keyEquivalent = keyEquivalent
        isSeparatorItem = false
    }

    public convenience init() { self.init(title: "", action: nil, keyEquivalent: "") }

    private init(separator: Void) {
        title = ""
        keyEquivalent = ""
        isSeparatorItem = true
    }

    public static func separator() -> NSMenuItem { NSMenuItem(separator: ()) }

    /// Runs the item's action against its target (or the key window's responder chain).
    func perform() {
        if let handler { handler(self); return }
        guard let action else { return }
        NSApplication.shared.sendAction(action, to: target, from: self)
    }
}
