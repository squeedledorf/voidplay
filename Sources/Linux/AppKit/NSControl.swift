import Foundation
import CoreGraphics

public enum NSControlSize: UInt, Sendable { case regular, small, mini, large }

/// Base of the standard controls: target/action, enabled state, font and alignment.
open class NSControl: NSView {
    open var target: AnyObject?
    open var action: Selector?
    open var isEnabled = true { didSet { needsDisplay = true } }
    open var font: NSFont? { didSet { needsDisplay = true } }
    open var alignment: NSTextAlignment = .natural { didSet { needsDisplay = true } }
    open var lineBreakMode: NSLineBreakMode = .byWordWrapping { didSet { needsDisplay = true } }
    open var controlSize: NSControlSize = .regular
    open var stringValue: String = "" { didSet { needsDisplay = true } }
    open var doubleValue: Double {
        get { Double(stringValue) ?? 0 }
        set { stringValue = String(newValue) }
    }
    open var integerValue: Int {
        get { Int(stringValue) ?? 0 }
        set { stringValue = String(newValue) }
    }
    open var attributedStringValue: NSAttributedString {
        get { NSAttributedString(string: stringValue) }
        set { stringValue = newValue.string }
    }

    @discardableResult
    open func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard let action, let receiver = (target as AnyObject?) ?? self.target else { return false }
        return SelectorRegistry.invoke(action, on: receiver, sender: self)
    }

    open func sizeToFit() {}
}

/// Text field. Labels draw their text; editing goes through a GtkEntry once a view needs it.
/// ponytail: no text editing yet — the classic windows only show labels.
open class NSTextField: NSControl {
    open var textColor: NSColor? = .labelColor { didSet { needsDisplay = true } }
    open var backgroundColor: NSColor? { didSet { needsDisplay = true } }
    open var drawsBackground = false
    open var isBordered = false
    open var isBezeled = false
    open var isEditable = false
    open var isSelectable = false
    open var placeholderString: String?
    open var maximumNumberOfLines = 1
    open var usesSingleLineMode = true
    open var preferredMaxLayoutWidth: CGFloat = 0
    open weak var delegate: AnyObject?

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { nil }

    public convenience init(labelWithString string: String) {
        self.init(frame: .zero)
        stringValue = string
        lineBreakMode = .byClipping
        sizeToFit()
    }

    public convenience init(wrappingLabelWithString string: String) {
        self.init(frame: .zero)
        stringValue = string
        maximumNumberOfLines = 0
        usesSingleLineMode = false
        sizeToFit()
    }

    public convenience init(string: String) {
        self.init(frame: .zero)
        stringValue = string
        isEditable = true
        isBezeled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = lineBreakMode
        return [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: (isEnabled ? textColor : textColor?.withAlphaComponent(0.5)) ?? NSColor.labelColor,
                .paragraphStyle: style]
    }

    open override var intrinsicContentSize: NSSize {
        let size = stringValue.size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 4, height: ceil(size.height) + 2)
    }

    open override func sizeToFit() { setFrameSize(intrinsicContentSize) }

    open override func draw(_ dirtyRect: NSRect) {
        if drawsBackground, let backgroundColor {
            backgroundColor.setFill()
            bounds.fill()
        }
        let text = stringValue.isEmpty ? (placeholderString ?? "") : stringValue
        let inset = bounds.insetBy(dx: 2, dy: 0)
        text.draw(in: inset, withAttributes: attributes)
    }
}

/// Progress spinner or bar, drawn with Core Graphics.
open class NSProgressIndicator: NSView {
    public enum Style: UInt, Sendable { case bar, spinning }
    open var style: Style = .bar
    open var controlSize: NSControlSize = .regular
    open var isIndeterminate = true
    open var minValue: Double = 0
    open var maxValue: Double = 100
    open var doubleValue: Double = 0 { didSet { needsDisplay = true } }
    open var isDisplayedWhenStopped = true
    private var timer: Timer?
    private var phase: CGFloat = 0

    open func startAnimation(_ sender: Any?) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase += .pi / 6
                self.needsDisplay = true
            }
        }
    }

    open func stopAnimation(_ sender: Any?) {
        timer?.invalidate()
        timer = nil
        needsDisplay = true
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if style == .spinning {
            guard timer != nil || isDisplayedWhenStopped else { return }
            let center = CGPoint(x: bounds.midX, y: bounds.midY), radius = min(bounds.width, bounds.height) / 2 - 1
            for i in 0..<12 {
                let angle = phase + CGFloat(i) * .pi / 6
                ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: CGFloat(i + 1) / 12)
                ctx.setLineWidth(1.5)
                ctx.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.45, y: center.y + sin(angle) * radius * 0.45))
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                ctx.strokePath()
            }
        } else {
            NSColor.controlBackgroundColor.setFill(); bounds.fill()
            let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: 0, width: bounds.width * CGFloat(max(0, min(1, fraction))), height: bounds.height).fill()
        }
    }
}
