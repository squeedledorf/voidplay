import Foundation
import CGtk

/// macOS virtual key codes for GDK keyvals, so upstream key handling (`event.keyCode == 49` …)
/// keeps working. Letters/digits map by US position, as macOS codes are positional.
enum KeyCodes {
    static func macKeyCode(for keyval: guint) -> UInt16 {
        let lower = gdk_keyval_to_lower(keyval)
        if let code = table[lower] { return code }
        return 0xFFFF
    }

    /// AppKit's private-use characters for function keys (NSUpArrowFunctionKey …).
    static func functionCharacter(for keyval: guint) -> String? {
        let scalar: UInt32?
        switch Int32(keyval) {
        case GDK_KEY_Up: scalar = 0xF700
        case GDK_KEY_Down: scalar = 0xF701
        case GDK_KEY_Left: scalar = 0xF702
        case GDK_KEY_Right: scalar = 0xF703
        case GDK_KEY_F1...GDK_KEY_F12: scalar = 0xF704 + UInt32(Int32(keyval) - GDK_KEY_F1)
        case GDK_KEY_Home: scalar = 0xF729
        case GDK_KEY_End: scalar = 0xF72B
        case GDK_KEY_Page_Up: scalar = 0xF72C
        case GDK_KEY_Page_Down: scalar = 0xF72D
        case GDK_KEY_Delete: scalar = 0xF728
        case GDK_KEY_BackSpace: scalar = 0x7F
        case GDK_KEY_Return, GDK_KEY_KP_Enter: scalar = 0x0D
        case GDK_KEY_Escape: scalar = 0x1B
        case GDK_KEY_Tab: scalar = 0x09
        default: scalar = nil
        }
        return scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }

    private static let table: [guint: UInt16] = {
        var t: [guint: UInt16] = [:]
        let letters: [(Character, UInt16)] = [("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
            ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31),
            ("u", 32), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46)]
        for (c, code) in letters { t[guint(c.asciiValue!)] = code }
        let digits: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (i, code) in digits.enumerated() { t[guint(48 + i)] = code }
        let keys: [(Int32, UInt16)] = [(GDK_KEY_Return, 36), (GDK_KEY_KP_Enter, 76), (GDK_KEY_Tab, 48), (GDK_KEY_space, 49),
            (GDK_KEY_BackSpace, 51), (GDK_KEY_Escape, 53), (GDK_KEY_Delete, 117), (GDK_KEY_Home, 115), (GDK_KEY_End, 119),
            (GDK_KEY_Page_Up, 116), (GDK_KEY_Page_Down, 121), (GDK_KEY_Left, 123), (GDK_KEY_Right, 124),
            (GDK_KEY_Down, 125), (GDK_KEY_Up, 126), (GDK_KEY_minus, 27), (GDK_KEY_equal, 24), (GDK_KEY_bracketleft, 33),
            (GDK_KEY_bracketright, 30), (GDK_KEY_semicolon, 41), (GDK_KEY_apostrophe, 39), (GDK_KEY_comma, 43),
            (GDK_KEY_period, 47), (GDK_KEY_slash, 44), (GDK_KEY_backslash, 42), (GDK_KEY_grave, 50),
            (GDK_KEY_F1, 122), (GDK_KEY_F2, 120), (GDK_KEY_F3, 99), (GDK_KEY_F4, 118), (GDK_KEY_F5, 96), (GDK_KEY_F6, 97),
            (GDK_KEY_F7, 98), (GDK_KEY_F8, 100), (GDK_KEY_F9, 101), (GDK_KEY_F10, 109), (GDK_KEY_F11, 103), (GDK_KEY_F12, 111),
            (GDK_KEY_KP_Add, 69), (GDK_KEY_KP_Subtract, 78)]
        for (k, code) in keys { t[guint(k)] = code }
        return t
    }()
}

public let NSUpArrowFunctionKey = 0xF700
public let NSDownArrowFunctionKey = 0xF701
public let NSLeftArrowFunctionKey = 0xF702
public let NSRightArrowFunctionKey = 0xF703
public let NSDeleteFunctionKey = 0xF728
public let NSHomeFunctionKey = 0xF729
public let NSEndFunctionKey = 0xF72B
public let NSPageUpFunctionKey = 0xF72C
public let NSPageDownFunctionKey = 0xF72D
