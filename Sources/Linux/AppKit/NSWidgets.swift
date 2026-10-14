import Foundation
import CoreGraphics

// The few standard controls upstream's WMP views use, drawn with Core Graphics like the rest of
// the stand-in: a push button, a pop-up menu button and an image view.
// ponytail: plain looks (rounded box, centred title); theming comes if a non-skinned window needs it.

public enum NSFocusRingType: UInt, Sendable { case `default`, none, exterior }

public protocol NSTextFieldDelegate: AnyObject {
    func controlTextDidChange(_ notification: Notification)
    func controlTextDidEndEditing(_ notification: Notification)
    func controlTextDidBeginEditing(_ notification: Notification)
}

extension NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {}
    public func controlTextDidEndEditing(_ notification: Notification) {}
    public func controlTextDidBeginEditing(_ notification: Notification) {}
}

/// Push button: draws its title in a rounded box and sends its action on a click released inside.
open class NSButton: NSControl {
    public enum BezelStyle: UInt, Sendable { case rounded = 1, regularSquare, texturedRounded = 11, recessed = 13, inline = 15 }
    public enum ButtonType: UInt, Sendable { case momentaryLight, pushOnPushOff, toggle, `switch`, radio, momentaryChange, onOff, momentaryPushIn }

    open var title: String { get { stringValue } set { stringValue = newValue } }
    open var image: NSImage? { didSet { needsDisplay = true } }
    open var bezelStyle: BezelStyle = .rounded
    open var isBordered = true
    open var state: NSControl.StateValue = .off { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { nil }

    public convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        self.title = title
        self.target = target
        self.action = action
        sizeToFit()
    }

    open func setButtonType(_ type: ButtonType) {}

    open override var intrinsicContentSize: NSSize {
        let size = title.size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        return NSSize(width: ceil(size.width) + 20, height: max(22, ceil(size.height) + 8))
    }

    open override func sizeToFit() { setFrameSize(intrinsicContentSize) }

    open override func draw(_ dirtyRect: NSRect) {
        if isBordered {
            let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            (pressed || state == .on ? NSColor.controlAccentColor.withAlphaComponent(0.35) : NSColor.controlColor).setFill()
            box.fill()
            NSColor.separatorColor.setStroke()
            box.stroke()
        }
        if let image {
            let side = min(bounds.width, bounds.height) - 4
            image.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side))
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor,
            .paragraphStyle: style]
        let height = title.size(withAttributes: attributes).height
        title.draw(in: NSRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height), withAttributes: attributes)
    }

    open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
    }

    open override func mouseDragged(with event: NSEvent) {
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    open override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        sendAction(action, to: target)
    }
}

extension NSControl {
    public struct StateValue: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let off = StateValue(rawValue: 0)
        public static let on = StateValue(rawValue: 1)
        public static let mixed = StateValue(rawValue: -1)
    }
}

/// Pop-up button: shows the selected title; a click opens the item list as a menu.
open class NSPopUpButton: NSButton {
    private var titles: [String] = []
    open private(set) var indexOfSelectedItem = -1 { didSet { needsDisplay = true } }
    open var pullsDown = false

    public init(frame frameRect: NSRect, pullsDown: Bool) {
        self.pullsDown = pullsDown
        super.init(frame: frameRect)
    }

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { nil }

    open var itemTitles: [String] { titles }
    open var numberOfItems: Int { titles.count }
    open var titleOfSelectedItem: String? { titles.indices.contains(indexOfSelectedItem) ? titles[indexOfSelectedItem] : nil }
    open override var title: String { get { titleOfSelectedItem ?? "" } set {} }

    open func removeAllItems() { titles = []; indexOfSelectedItem = -1 }
    open func addItem(withTitle title: String) { addItems(withTitles: [title]) }
    open func addItems(withTitles itemTitles: [String]) {
        titles += itemTitles
        if indexOfSelectedItem < 0, !titles.isEmpty { indexOfSelectedItem = 0 }
    }
    open func selectItem(at index: Int) { indexOfSelectedItem = titles.indices.contains(index) ? index : -1 }
    open func selectItem(withTitle title: String) { selectItem(at: titles.firstIndex(of: title) ?? -1) }
    open func itemTitle(at index: Int) -> String { titles.indices.contains(index) ? titles[index] : "" }

    open override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Chevron at the right edge.
        let x = bounds.maxX - 12, y = bounds.midY
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: x - 3, y: y + 1.5))
        chevron.line(to: NSPoint(x: x, y: y - 1.5))
        chevron.line(to: NSPoint(x: x + 3, y: y + 1.5))
        NSColor.secondaryLabelColor.setStroke()
        chevron.stroke()
    }

    open override func mouseDown(with event: NSEvent) {
        guard isEnabled, !titles.isEmpty else { return }
        let menu = NSMenu()
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.state = index == indexOfSelectedItem ? .on : .off
            item.handler = { [weak self] _ in
                guard let self else { return }
                self.selectItem(at: index)
                self.sendAction(self.action, to: self.target)
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }

    open override func mouseUp(with event: NSEvent) {}
}

/// Image view: draws its image scaled into its bounds.
open class NSImageView: NSControl {
    public enum ImageScaling: UInt, Sendable { case scaleProportionallyDown, scaleAxesIndependently, scaleNone, scaleProportionallyUpOrDown }
    open var image: NSImage? { didSet { needsDisplay = true } }
    open var imageScaling: ImageScaling = .scaleProportionallyDown
    public enum ImageAlignment: UInt, Sendable { case alignCenter, alignTop, alignTopLeft, alignTopRight, alignLeft, alignBottom, alignBottomLeft, alignBottomRight, alignRight }
    open var imageAlignment: ImageAlignment = .alignCenter
    open var isEditable = false

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { nil }
    public convenience init(image: NSImage) {
        self.init(frame: NSRect(origin: .zero, size: image.size))
        self.image = image
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        var rect = bounds
        switch imageScaling {
        case .scaleAxesIndependently: break
        case .scaleNone:
            rect = NSRect(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2,
                          width: image.size.width, height: image.size.height)
        case .scaleProportionallyDown, .scaleProportionallyUpOrDown:
            var scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            if imageScaling == .scaleProportionallyDown { scale = min(scale, 1) }
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        }
        image.draw(in: rect)
    }
}

// MARK: Tooltips and accessibility (recorded; shown once tooltips are wired to GTK)

public protocol NSViewToolTipOwner: AnyObject {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String
}

extension NSView {
    public typealias ToolTipTag = Int

    @discardableResult
    public func addToolTip(_ rect: NSRect, owner: AnyObject, userData data: UnsafeMutableRawPointer?) -> ToolTipTag { 0 }
    public func removeAllToolTips() {}
    public func setAccessibilityValue(_ value: Any?) {}
}

extension NSTextField {
    public func currentEditor() -> NSView? { nil }
}

@preconcurrency @MainActor public var NSApp: NSApplication { NSApplication.shared }
