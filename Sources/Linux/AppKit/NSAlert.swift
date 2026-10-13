import Foundation
import CGtk

/// Modal alert as a small GTK window: message, detail, an optional text field (an `NSTextField`
/// accessory becomes a GtkEntry and its text comes back in `stringValue`), and the buttons in
/// AppKit's order (first button rightmost and default; Escape or closing picks "Cancel" if present,
/// else the last button). Before the app runs (CLI, tests) it reports to stderr and answers `.cancel`.
///
/// ponytail: other accessory views and the suppression checkbox are not shown.
@preconcurrency @MainActor
public final class NSAlert {
    public enum Style { case warning, informational, critical }

    public var messageText = ""
    public var informativeText = ""
    public var alertStyle: Style = .warning
    public var accessoryView: NSView?
    public var icon: NSImage?
    public var showsSuppressionButton = false
    public var window: NSWindow? { nil }
    private var buttonTitles: [String] = []

    public init() {}

    public func addButton(withTitle title: String) { buttonTitles.append(title) }

    /// The alert being shown: its answer, and the loop waiting for it.
    private static var answer: Int?
    private static var loop: OpaquePointer?

    @discardableResult
    public func runModal() -> NSApplication.ModalResponse {
        guard NSApplication.shared.isRunning else {
            let detail = informativeText.isEmpty ? "" : ": \(informativeText)"
            FileHandle.standardError.write(Data("\(messageText)\(detail)\n".utf8))
            return .cancel
        }
        let titles = buttonTitles.isEmpty ? ["OK"] : buttonTitles
        let cancelIndex = titles.firstIndex { $0 == "Cancel" } ?? titles.count - 1

        let window = gtk_window_new()!
        let gtkWindow = cgtk_window(window)
        gtk_window_set_title(gtkWindow, messageText)
        gtk_window_set_modal(gtkWindow, 1)
        gtk_window_set_resizable(gtkWindow, 0)
        if let parent = NSWindow.all.first(where: { $0.isKeyWindow }) ?? NSWindow.all.first(where: { $0.isVisible }) {
            gtk_window_set_transient_for(gtkWindow, parent.gtkWindowPtr)
        }

        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)!
        for side in [gtk_widget_set_margin_top, gtk_widget_set_margin_bottom,
                     gtk_widget_set_margin_start, gtk_widget_set_margin_end] { side(box, 18) }
        func label(_ text: String, css: String?) {
            let label = gtk_label_new(text)!
            gtk_label_set_wrap(gcast(label), 1)
            gtk_label_set_max_width_chars(gcast(label), 50)
            gtk_label_set_xalign(gcast(label), 0)
            if let css { gtk_widget_add_css_class(label, css) }
            gtk_box_append(gcast(box), label)
        }
        label(messageText, css: "title-4")
        if !informativeText.isEmpty { label(informativeText, css: nil) }

        let field = accessoryView as? NSTextField
        var entry: UnsafeMutablePointer<GtkWidget>?
        if let field {
            entry = gtk_entry_new()
            gtk_editable_set_text(gcast(entry), field.stringValue)
            if let placeholder = field.placeholderString { gtk_entry_set_placeholder_text(gcast(entry), placeholder) }
            gtk_entry_set_activates_default(gcast(entry), 1)
            gtk_widget_set_size_request(entry, max(300, Int32(field.frame.width)), -1)
            gtk_box_append(gcast(box), entry)
        }

        typealias Clicked = @convention(c) (OpaquePointer?, gpointer?) -> Void
        let onClicked: Clicked = { _, data in
            NSAlert.answer = Int(bitPattern: data) - 1
            if let loop = NSAlert.loop { g_main_loop_quit(loop) }
        }
        let buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
        gtk_widget_set_halign(buttons, GTK_ALIGN_END)
        gtk_widget_set_margin_top(buttons, 6)
        for (index, title) in titles.enumerated().reversed() {
            let button = gtk_button_new_with_label(title)!
            if index == 0 {
                gtk_widget_add_css_class(button, "suggested-action")
                gtk_window_set_default_widget(gtkWindow, button)
            }
            cgtk_signal_connect(gcast(button), "clicked", unsafeBitCast(onClicked, to: GCallback.self),
                                UnsafeMutableRawPointer(bitPattern: index + 1))
            gtk_box_append(gcast(buttons), button)
        }
        gtk_box_append(gcast(box), buttons)
        gtk_window_set_child(gtkWindow, box)

        typealias CloseRequest = @convention(c) (OpaquePointer?, gpointer?) -> gboolean
        let onClose: CloseRequest = { _, data in
            NSAlert.answer = Int(bitPattern: data) - 1
            if let loop = NSAlert.loop { g_main_loop_quit(loop) }
            return 1  // closed below, once the answer is read
        }
        cgtk_signal_connect(gcast(window), "close-request", unsafeBitCast(onClose, to: GCallback.self),
                            UnsafeMutableRawPointer(bitPattern: cancelIndex + 1))
        // Escape closes the window, i.e. answers like Cancel.
        let escape = gtk_shortcut_controller_new()!
        gtk_shortcut_controller_add_shortcut(gcast(escape),
            gtk_shortcut_new(gtk_shortcut_trigger_parse_string("Escape"), gtk_named_action_new("window.close")))
        gtk_widget_add_controller(window, gcast(escape))

        let outer = (Self.answer, Self.loop)  // an alert opened from another alert's action
        Self.answer = nil
        Self.loop = g_main_loop_new(nil, 0)
        gtk_window_present(gtkWindow)
        if let entry { gtk_widget_grab_focus(entry) }
        g_main_loop_run(Self.loop)
        g_main_loop_unref(Self.loop)
        let answer = Self.answer ?? cancelIndex
        (Self.answer, Self.loop) = outer

        if let field, let entry { field.stringValue = String(cString: gtk_editable_get_text(gcast(entry))) }
        gtk_window_destroy(gtkWindow)
        return NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + answer)
    }
}
