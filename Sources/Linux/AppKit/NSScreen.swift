import Foundation
import CGtk

/// A monitor, in AppKit's global space: the primary screen's bottom-left corner is (0, 0), y up.
@preconcurrency @MainActor
open class NSScreen {
    public let frame: NSRect
    public let visibleFrame: NSRect
    public let backingScaleFactor: CGFloat
    public let localizedName: String
    /// Top-left logical geometry, as GDK and the compositor report it.
    let layoutFrame: NSRect

    init(frame: NSRect, visibleFrame: NSRect, scale: CGFloat, name: String, layout: NSRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = scale
        self.localizedName = name
        self.layoutFrame = layout
    }

    public var deviceDescription: [NSDeviceDescriptionKey: Any] { [:] }

    /// Primary first. The primary is the monitor at layout (0, 0), else the first one.
    public static var screens: [NSScreen] {
        guard let display = gdk_display_get_default(), let monitors = gdk_display_get_monitors(display) else { return [] }
        var layouts: [(rect: NSRect, scale: CGFloat, name: String)] = []
        for i in 0..<g_list_model_get_n_items(monitors) {
            guard let item = g_list_model_get_item(monitors, i) else { continue }
            let monitor = OpaquePointer(item)
            var geometry = GdkRectangle()
            gdk_monitor_get_geometry(monitor, &geometry)
            let name = gdk_monitor_get_connector(monitor).map { String(cString: $0) } ?? "Monitor \(i)"
            layouts.append((NSRect(x: CGFloat(geometry.x), y: CGFloat(geometry.y),
                                   width: CGFloat(geometry.width), height: CGFloat(geometry.height)),
                            CGFloat(gdk_monitor_get_scale(monitor)), name))
            g_object_unref(item)
        }
        if let primary = layouts.firstIndex(where: { $0.rect.origin == .zero }), primary > 0 {
            layouts.insert(layouts.remove(at: primary), at: 0)
        }
        guard let primaryHeight = layouts.first?.rect.height else { return [] }
        return layouts.map { layout in
            let frame = NSRect(x: layout.rect.minX, y: primaryHeight - layout.rect.maxY,
                               width: layout.rect.width, height: layout.rect.height)
            let insets = WindowPlacement.shared.reservedInsets(forMonitor: layout.name)
            let visible = NSRect(x: frame.minX + insets.left, y: frame.minY + insets.bottom,
                                 width: frame.width - insets.left - insets.right,
                                 height: frame.height - insets.top - insets.bottom)
            return NSScreen(frame: frame, visibleFrame: visible, scale: layout.scale, name: layout.name, layout: layout.rect)
        }
    }

    public static var main: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(pointer) } ?? screens.first
    }

    /// Height of the primary screen: the pivot between AppKit's y-up and the compositor's y-down.
    static var primaryHeight: CGFloat { screens.first?.frame.height ?? 1080 }

    /// AppKit screen rect → compositor top-left point.
    static func layoutTopLeft(of rect: NSRect) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryHeight - rect.maxY)
    }

    /// Compositor top-left point + size → AppKit screen origin.
    static func appKitOrigin(layoutTopLeft point: CGPoint, height: CGFloat) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - point.y - height)
    }
}

public struct NSDeviceDescriptionKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}
