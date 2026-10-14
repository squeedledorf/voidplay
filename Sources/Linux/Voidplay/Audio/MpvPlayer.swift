import Foundation
import CMpv

/// Thin owner of one libmpv handle. Events are read on a private thread and delivered on main.
final class MpvPlayer {
    enum EndReason { case eof, stop, quit, error, redirect, unknown }

    enum Event {
        case fileLoaded
        case endFile(reason: EndReason, error: String?)
        case property(String, Any?)
    }

    var onEvent: ((Event) -> Void)?

    private let handle: OpaquePointer
    private var eventThread: Thread?

    init?(options: [String: String]) {
        guard let handle = mpv_create() else { return nil }
        self.handle = handle
        for (key, value) in options {
            mpv_set_option_string(handle, key, value)
        }
        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            return nil
        }
        observe("time-pos", MPV_FORMAT_DOUBLE)
        observe("duration", MPV_FORMAT_DOUBLE)
        observe("pause", MPV_FORMAT_FLAG)
        observe("playlist-pos", MPV_FORMAT_INT64)
        observe("metadata", MPV_FORMAT_NODE)
        observe("audio-bitrate", MPV_FORMAT_DOUBLE)
        let thread = Thread { [weak self] in self?.eventLoop() }
        thread.name = "mpv-events"
        eventThread = thread
        thread.start()
    }

    deinit {
        mpv_terminate_destroy(handle)
    }

    // MARK: Commands and properties

    @discardableResult
    func command(_ args: String...) -> Bool {
        var cStrings = args.map { strdup($0) } + [nil]
        defer { cStrings.forEach { free($0) } }
        return cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                mpv_command(handle, $0) >= 0
            }
        }
    }

    @discardableResult
    func set(_ name: String, _ value: String) -> Bool {
        mpv_set_property_string(handle, name, value) >= 0
    }

    func set(_ name: String, _ value: Double) {
        var v = value
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &v)
    }

    func set(_ name: String, _ value: Bool) {
        var v: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &v)
    }

    func double(_ name: String) -> Double? {
        var v = 0.0
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &v) >= 0 ? v : nil
    }

    func int(_ name: String) -> Int? {
        var v: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &v) >= 0 ? Int(v) : nil
    }

    func string(_ name: String) -> String? {
        guard let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    func node(_ name: String) -> Any? {
        var node = mpv_node()
        guard mpv_get_property(handle, name, MPV_FORMAT_NODE, &node) >= 0 else { return nil }
        defer { mpv_free_node_contents(&node) }
        return Self.convert(node)
    }

    // MARK: Events

    private func observe(_ name: String, _ format: mpv_format) {
        mpv_observe_property(handle, 0, name, format)
    }

    private func eventLoop() {
        while true {
            guard let event = mpv_wait_event(handle, -1)?.pointee else { continue }
            let converted: Event?
            switch event.event_id {
            case MPV_EVENT_SHUTDOWN:
                return
            case MPV_EVENT_FILE_LOADED:
                converted = .fileLoaded
            case MPV_EVENT_END_FILE:
                let end = event.data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                let reason: EndReason
                switch end.reason {
                case MPV_END_FILE_REASON_EOF: reason = .eof
                case MPV_END_FILE_REASON_STOP: reason = .stop
                case MPV_END_FILE_REASON_QUIT: reason = .quit
                case MPV_END_FILE_REASON_ERROR: reason = .error
                case MPV_END_FILE_REASON_REDIRECT: reason = .redirect
                default: reason = .unknown
                }
                let message = end.error < 0 ? String(cString: mpv_error_string(end.error)) : nil
                converted = .endFile(reason: reason, error: message)
            case MPV_EVENT_PROPERTY_CHANGE:
                let prop = event.data.assumingMemoryBound(to: mpv_event_property.self).pointee
                let name = String(cString: prop.name)
                var value: Any?
                if let data = prop.data {
                    switch prop.format {
                    case MPV_FORMAT_DOUBLE: value = data.assumingMemoryBound(to: Double.self).pointee
                    case MPV_FORMAT_FLAG: value = data.assumingMemoryBound(to: Int32.self).pointee != 0
                    case MPV_FORMAT_INT64: value = Int(data.assumingMemoryBound(to: Int64.self).pointee)
                    case MPV_FORMAT_NODE: value = Self.convert(data.assumingMemoryBound(to: mpv_node.self).pointee)
                    default: value = nil
                    }
                }
                converted = .property(name, value)
            default:
                converted = nil
            }
            if let converted {
                DispatchQueue.main.async { [weak self] in self?.onEvent?(converted) }
            }
        }
    }

    private static func convert(_ node: mpv_node) -> Any? {
        switch node.format {
        case MPV_FORMAT_STRING: return node.u.string.map { String(cString: $0) }
        case MPV_FORMAT_FLAG: return node.u.flag != 0
        case MPV_FORMAT_INT64: return Int(node.u.int64)
        case MPV_FORMAT_DOUBLE: return node.u.double_
        case MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list?.pointee else { return [Any]() }
            return (0..<Int(list.num)).compactMap { convert(list.values[$0]) }
        case MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list?.pointee else { return [String: Any]() }
            var map: [String: Any] = [:]
            for i in 0..<Int(list.num) {
                if let key = list.keys[i], let value = convert(list.values[i]) {
                    map[String(cString: key)] = value
                }
            }
            return map
        default:
            return nil
        }
    }
}
