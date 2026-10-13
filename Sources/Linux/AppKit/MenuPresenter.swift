import Foundation
import CGtk

/// Shows an NSMenu as a GtkPopoverMenu anchored at a point in a window.
enum MenuPresenter {
    private final class Presentation {
        var items: [NSMenuItem] = []
        var popover: UnsafeMutablePointer<GtkWidget>?
        var menus: [NSMenu] = []
    }

    private static var current: Presentation?

    static func dismissAll() {
        if let popover = current?.popover { gtk_popover_popdown(gcast(popover)) }
    }

    static func present(_ menu: NSMenu, at location: NSPoint, in window: NSWindow?) {
        guard let window else { return }
        dismissAll()
        let presentation = Presentation()
        current = presentation
        let group = g_simple_action_group_new()
        let model = build(menu, presentation: presentation, group: gcast(group))
        gtk_widget_insert_action_group(window.canvas, "voidplay", gcast(group))
        g_object_unref(gcast(group))

        let popover = gtk_popover_menu_new_from_model(gcast(model))!
        g_object_unref(gcast(model))
        presentation.popover = popover
        gtk_widget_set_parent(popover, window.canvas)
        gtk_popover_set_has_arrow(gcast(popover), 0)
        var rect = GdkRectangle(x: Int32(location.x), y: Int32(window.frame.height - location.y), width: 1, height: 1)
        gtk_popover_set_pointing_to(gcast(popover), &rect)
        gtk_popover_set_position(gcast(popover), GTK_POS_BOTTOM)

        typealias Closed = @convention(c) (OpaquePointer?, gpointer?) -> Void
        let onClosed: Closed = { popover, _ in
            guard let popover else { return }
            let widget = UnsafeMutablePointer<GtkWidget>(popover)
            DispatchQueue.main.async {
                gtk_widget_unparent(widget)
                for menu in MenuPresenter.current?.menus ?? [] { menu.delegate?.menuDidClose(menu) }
                if MenuPresenter.current?.popover == widget { MenuPresenter.current = nil }
            }
        }
        cgtk_signal_connect(gcast(popover), "closed", unsafeBitCast(onClosed, to: GCallback.self), nil)
        for m in presentation.menus { m.delegate?.menuWillOpen(m) }
        gtk_popover_popup(gcast(popover))
    }

    /// GMenu for `menu`; separators split sections, as GTK draws them.
    private static func build(_ menu: NSMenu, presentation: Presentation,
                              group: OpaquePointer?) -> OpaquePointer {
        menu.delegate?.menuNeedsUpdate(menu)
        presentation.menus.append(menu)
        let root = g_menu_new()!
        var section = g_menu_new()!
        func flush() {
            if g_menu_model_get_n_items(gcast(section)) > 0 {
                g_menu_append_section(root, nil, gcast(section))
            }
            g_object_unref(gcast(section))
            section = g_menu_new()!
        }
        for item in menu.items where !item.isHidden {
            if item.isSeparatorItem { flush(); continue }
            let label = item.title.replacingOccurrences(of: "_", with: "__")
            if let submenu = item.submenu {
                let model = build(submenu, presentation: presentation, group: group)
                g_menu_append_submenu(section, label, gcast(model))
                g_object_unref(gcast(model))
                continue
            }
            let index = presentation.items.count
            presentation.items.append(item)
            let name = "m\(index)"
            let action: OpaquePointer?
            if item.state == .on {
                action = g_simple_action_new_stateful(name, nil, g_variant_new_boolean(1))
            } else {
                action = g_simple_action_new(name, nil)
            }
            g_simple_action_set_enabled(action, item.isEnabled && (item.action != nil || item.handler != nil) ? 1 : 0)
            typealias Activate = @convention(c) (OpaquePointer?, OpaquePointer?, gpointer?) -> Void
            let onActivate: Activate = { _, _, data in
                let index = Int(bitPattern: data)
                guard let items = MenuPresenter.current?.items, items.indices.contains(index) else { return }
                let item = items[index]
                DispatchQueue.main.async { item.perform() }
            }
            cgtk_signal_connect(gcast(action), "activate", unsafeBitCast(onActivate, to: GCallback.self),
                                UnsafeMutableRawPointer(bitPattern: index))
            g_action_map_add_action(gcast(group), gcast(action))
            g_object_unref(gcast(action))
            g_menu_append(section, label, "voidplay.\(name)")
        }
        flush()
        g_object_unref(gcast(section))
        return root
    }
}
