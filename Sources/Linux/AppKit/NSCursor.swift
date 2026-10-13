import Foundation
import CGtk

/// Pointer shape, applied to the window under the pointer by CSS cursor name.
open class NSCursor {
    let name: String

    init(name: String) { self.name = name }

    public static let arrow = NSCursor(name: "default")
    public static let pointingHand = NSCursor(name: "pointer")
    public static let iBeam = NSCursor(name: "text")
    public static let crosshair = NSCursor(name: "crosshair")
    public static let openHand = NSCursor(name: "grab")
    public static let closedHand = NSCursor(name: "grabbing")
    public static let resizeLeftRight = NSCursor(name: "ew-resize")
    public static let resizeUpDown = NSCursor(name: "ns-resize")
    public static let resizeLeft = NSCursor(name: "w-resize")
    public static let resizeRight = NSCursor(name: "e-resize")
    public static let resizeUp = NSCursor(name: "n-resize")
    public static let resizeDown = NSCursor(name: "s-resize")
    public static let operationNotAllowed = NSCursor(name: "not-allowed")
    public static let dragCopy = NSCursor(name: "copy")
    public static let contextualMenu = NSCursor(name: "context-menu")
    public static let disappearingItem = NSCursor(name: "default")

    public static var current: NSCursor = .arrow
    private static var stack: [NSCursor] = []

    open func set() {
        NSCursor.current = self
        for window in NSWindow.all where window.isVisible {
            gtk_widget_set_cursor_from_name(window.canvas, name)
        }
    }

    open func push() { NSCursor.stack.append(NSCursor.current); set() }
    open func pop() { NSCursor.pop() }
    public static func pop() { (stack.popLast() ?? .arrow).set() }
    public static func hide() {}
    public static func unhide() {}
    public static func setHiddenUntilMouseMoves(_ flag: Bool) {}
}
