import AppKit

/// One column of a `<PLAYLIST>`'s `columns` attribute: the media attribute it shows and its label.
///
/// `Headspace` declares `columns="name=Name;Duration=Time"` with `columnsVisible="false"`: WMP 7
/// drew each item as its name with the time right-aligned beside it, under no header. The single
/// title line a skin gets when it declares no columns stays as it was.
struct WMPPlaylistColumn: Equatable {
    let attribute: String
    let label: String

    /// `name=Name;Duration=Time` → two columns; nil when nothing is declared.
    static func parse(_ declaration: String?) -> [WMPPlaylistColumn]? {
        let columns = (declaration ?? "").split(separator: ";").compactMap { entry -> WMPPlaylistColumn? in
            let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let attribute = parts.first, !attribute.isEmpty else { return nil }
            return WMPPlaylistColumn(attribute: attribute, label: parts.count > 1 ? parts[1] : attribute)
        }
        return columns.isEmpty ? nil : columns
    }

    /// Sized to its widest value and right-aligned, as WMP drew Time; text columns share the rest.
    var isTime: Bool { attribute.caseInsensitiveCompare("duration") == .orderedSame }

    func value(of item: WMPPlaylistItemSnapshot) -> String {
        switch attribute.lowercased() {
        case "name", "title": return item.title
        case "artist", "author", "wm/albumartist": return item.artist
        case "duration":
            guard item.duration > 0 else { return "" }
            let seconds = Int(item.duration.rounded())
            return seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
        default: return ""
        }
    }
}

/// The list chrome WMP 7 borrowed from Windows: a check box per item (checked items play) and the
/// classic grey scroll bar, both in the system's colours rather than the skin's.
enum WMPClassicListChrome {
    static let scrollBarWidth: CGFloat = 16
    static let checkBoxSize: CGFloat = 13

    private static let face = NSColor(calibratedRed: 0.753, green: 0.753, blue: 0.753, alpha: 1)
    private static let shadow = NSColor(calibratedRed: 0.502, green: 0.502, blue: 0.502, alpha: 1)
    private static let darkShadow = NSColor(calibratedRed: 0.251, green: 0.251, blue: 0.251, alpha: 1)

    /// A sunken classic check box, ticked. `rect` is in a flipped view.
    static func drawCheckBox(in rect: NSRect) {
        let r = rect.integral
        shadow.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width - 1, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 1).fill()
        darkShadow.setFill(); NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 3, height: 1).fill()
        NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 3).fill()
        NSColor.white.setFill(); NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
        face.setFill(); NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1).fill()
        NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2).fill()
        NSColor.white.setFill(); r.insetBy(dx: 2, dy: 2).fill()
        // The tick: three pixels thick, down-right then up-right, as Windows drew it.
        NSColor.black.setFill()
        let x = r.minX + 3, y = r.minY + 3
        for column in 0..<7 {
            let top = y + CGFloat(column < 3 ? 2 + column : 6 - column)
            NSRect(x: x + CGFloat(column), y: top, width: 1, height: 3).fill()
        }
    }

    enum ScrollHit { case lineUp, lineDown, pageUp, pageDown, thumb }

    /// The thumb: proportional to the visible share of the list, never shorter than 8.
    static func thumbRect(in bar: NSRect, first: Int, visible: Int, total: Int) -> NSRect {
        let track = bar.insetBy(dx: 0, dy: scrollBarWidth)
        guard total > visible, track.height > 0 else { return track }
        let length = max(8, (track.height * CGFloat(visible) / CGFloat(total)).rounded())
        let travel = track.height - length
        let offset = (travel * CGFloat(first) / CGFloat(total - visible)).rounded()
        return NSRect(x: bar.minX, y: track.minY + offset, width: bar.width, height: length)
    }

    static func hit(_ point: NSPoint, in bar: NSRect, first: Int, visible: Int, total: Int) -> ScrollHit? {
        guard bar.contains(point) else { return nil }
        if point.y < bar.minY + scrollBarWidth { return .lineUp }
        if point.y >= bar.maxY - scrollBarWidth { return .lineDown }
        let thumb = thumbRect(in: bar, first: first, visible: visible, total: total)
        if point.y < thumb.minY { return .pageUp }
        if point.y >= thumb.maxY { return .pageDown }
        return .thumb
    }

    static func drawScrollBar(in bar: NSRect, first: Int, visible: Int, total: Int) {
        // The track is Windows' 50% white-on-silver dither; its average reads the same.
        NSColor(calibratedRed: 0.875, green: 0.875, blue: 0.875, alpha: 1).setFill()
        bar.fill()
        let up = NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: scrollBarWidth)
        let down = NSRect(x: bar.minX, y: bar.maxY - scrollBarWidth, width: bar.width, height: scrollBarWidth)
        drawRaised(up); drawArrow(in: up, pointingUp: true)
        drawRaised(down); drawArrow(in: down, pointingUp: false)
        drawRaised(thumbRect(in: bar, first: first, visible: visible, total: total))
    }

    /// A raised classic button face: light outer top-left, white inner, grey and black bottom-right.
    private static func drawRaised(_ rect: NSRect) {
        let r = rect.integral
        guard r.width >= 4, r.height >= 4 else { return }
        NSColor.black.setFill(); r.fill()
        shadow.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width - 1, height: r.height - 1).fill()
        face.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width - 1, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 1).fill()
        NSColor.white.setFill(); NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 3, height: r.height - 3).fill()
        face.setFill(); NSRect(x: r.minX + 2, y: r.minY + 2, width: r.width - 4, height: r.height - 4).fill()
    }

    private static func drawArrow(in rect: NSRect, pointingUp: Bool) {
        NSColor.black.setFill()
        let centreX = rect.midX.rounded(.down), top = rect.midY.rounded(.down) - 2
        for row in 0..<4 {
            let width = CGFloat(pointingUp ? 1 + 2 * row : 7 - 2 * row)
            NSRect(x: centreX - ((width - 1) / 2).rounded(.down), y: top + CGFloat(row), width: width, height: 1).fill()
        }
    }
}
