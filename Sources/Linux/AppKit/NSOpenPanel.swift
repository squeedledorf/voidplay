import Foundation
import UniformTypeIdentifiers
import CGtk

/// File chooser on GtkFileDialog. `runModal()` spins a nested main loop until the user answers,
/// as AppKit's modal session does; `begin` answers asynchronously.
@preconcurrency @MainActor
open class NSSavePanel: NSObject {
    open var title: String?
    open var message: String?
    open var prompt: String?
    open var nameFieldStringValue = ""
    open var directoryURL: URL?
    open var canCreateDirectories = true
    open var showsHiddenFiles = false
    open var treatsFilePackagesAsDirectories = false
    /// File extensions offered (Linux helper; upstream's UTType lists map onto it).
    open var allowedFileExtensions: [String] = []
    /// UTType list → the extensions the dialog filters on.
    open var allowedContentTypes: [UTType] {
        get { allowedFileExtensions.compactMap { UTType(filenameExtension: $0) } }
        set { allowedFileExtensions = newValue.flatMap(\.filenameExtensions) }
    }
    open var allowedFileTypes: [String]? {
        get { allowedFileExtensions.isEmpty ? nil : allowedFileExtensions }
        set { allowedFileExtensions = newValue ?? [] }
    }
    public internal(set) var urls: [URL] = []
    open var url: URL? { urls.first }

    public override init() { super.init() }

    enum Mode { case save, open, openMultiple, folder }
    var mode: Mode { .save }

    open func runModal() -> NSApplication.ModalResponse {
        var response: NSApplication.ModalResponse?
        let loop = g_main_loop_new(nil, 0)
        begin { result in
            response = result
            g_main_loop_quit(loop)
        }
        if response == nil { g_main_loop_run(loop) }
        g_main_loop_unref(loop)
        return response ?? .cancel
    }

    open func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        begin(completionHandler: handler)
    }

    open func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        let dialog = gtk_file_dialog_new()
        if let title { gtk_file_dialog_set_title(dialog, title) }
        if let prompt { gtk_file_dialog_set_accept_label(dialog, prompt) }
        gtk_file_dialog_set_modal(dialog, 1)
        if let directoryURL {
            let folder = g_file_new_for_path(directoryURL.path)
            gtk_file_dialog_set_initial_folder(dialog, folder)
            g_object_unref(gcast(folder))
        }
        if !nameFieldStringValue.isEmpty { gtk_file_dialog_set_initial_name(dialog, nameFieldStringValue) }
        if !allowedFileExtensions.isEmpty {
            let filter = gtk_file_filter_new()
            gtk_file_filter_set_name(filter, allowedFileExtensions.map { "*.\($0)" }.joined(separator: ", "))
            for ext in allowedFileExtensions { gtk_file_filter_add_suffix(filter, ext) }
            gtk_file_dialog_set_default_filter(dialog, filter)
            g_object_unref(gcast(filter))
        }
        let request = Request(panel: self, handler: handler, dialog: dialog)
        let parent = NSWindow.all.first { $0.isKeyWindow }?.gtkWindowPtr
        let data = Unmanaged.passRetained(request).toOpaque()
        typealias Done = @convention(c) (UnsafeMutablePointer<GObject>?, OpaquePointer?, gpointer?) -> Void
        let done: Done = { source, result, data in
            guard let data else { return }
            let request = Unmanaged<Request>.fromOpaque(data).takeRetainedValue()
            request.finish(result)
        }
        switch mode {
        case .open: gtk_file_dialog_open(dialog, parent, nil, done, data)
        case .openMultiple: gtk_file_dialog_open_multiple(dialog, parent, nil, done, data)
        case .folder: gtk_file_dialog_select_folder(dialog, parent, nil, done, data)
        case .save: gtk_file_dialog_save(dialog, parent, nil, done, data)
        }
    }

    @preconcurrency @MainActor
    final class Request {
        let panel: NSSavePanel
        let handler: (NSApplication.ModalResponse) -> Void
        let dialog: OpaquePointer?

        init(panel: NSSavePanel, handler: @escaping (NSApplication.ModalResponse) -> Void, dialog: OpaquePointer?) {
            self.panel = panel
            self.handler = handler
            self.dialog = dialog
        }

        func finish(_ result: OpaquePointer?) {
            var error: UnsafeMutablePointer<GError>?
            var files: [URL] = []
            func url(_ file: OpaquePointer?) -> URL? {
                guard let file, let path = g_file_get_path(file) else { return nil }
                defer { g_free(path) }
                return URL(fileURLWithPath: String(cString: path))
            }
            switch panel.mode {
            case .open:
                let file = gtk_file_dialog_open_finish(dialog, result, &error)
                files = url(file).map { [$0] } ?? []
                if let file { g_object_unref(gcast(file)) }
            case .folder:
                let file = gtk_file_dialog_select_folder_finish(dialog, result, &error)
                files = url(file).map { [$0] } ?? []
                if let file { g_object_unref(gcast(file)) }
            case .save:
                let file = gtk_file_dialog_save_finish(dialog, result, &error)
                files = url(file).map { [$0] } ?? []
                if let file { g_object_unref(gcast(file)) }
            case .openMultiple:
                if let list = gtk_file_dialog_open_multiple_finish(dialog, result, &error) {
                    for i in 0..<g_list_model_get_n_items(list) {
                        let item = g_list_model_get_item(list, i)
                        if let u = url(OpaquePointer(item)) { files.append(u) }
                        g_object_unref(item)
                    }
                    g_object_unref(gcast(list))
                }
            }
            if let error { g_error_free(error) }
            g_object_unref(gcast(dialog))
            panel.urls = files
            handler(files.isEmpty ? .cancel : .OK)
        }
    }
}

open class NSOpenPanel: NSSavePanel {
    open var canChooseFiles = true
    open var canChooseDirectories = false
    open var allowsMultipleSelection = false
    open var resolvesAliases = true

    override var mode: Mode {
        if canChooseDirectories && !canChooseFiles { return .folder }
        return allowsMultipleSelection ? .openMultiple : .open
    }

    public static func openPanel() -> NSOpenPanel { NSOpenPanel() }
}

extension NSSavePanel {
    public static func savePanel() -> NSSavePanel { NSSavePanel() }
}
