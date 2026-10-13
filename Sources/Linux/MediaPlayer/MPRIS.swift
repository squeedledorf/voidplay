import Foundation
import AppKit
import CGtk

// MPRIS 2 (org.mpris.MediaPlayer2 + .Player) on the session bus, fed by MPNowPlayingInfoCenter and
// driving MPRemoteCommandCenter. Runs on GLib's main context, i.e. the main thread.
//
// ponytail: no TrackList, Volume/Shuffle/LoopStatus/Rate are fixed (NowPlayingManager has no
// commands for them); add when a client needs them.

private let objectPath = "/org/mpris/MediaPlayer2"
private let rootInterface = "org.mpris.MediaPlayer2"
private let playerInterface = "org.mpris.MediaPlayer2.Player"

private let introspection = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

private func string(_ value: String) -> OpaquePointer { g_variant_new_string(value) }

private func stringArray(_ values: [String]) -> OpaquePointer {
    let children = values.map { Optional(string($0)) }
    if children.isEmpty {
        let type = g_variant_type_new("s")
        defer { g_variant_type_free(type) }
        return g_variant_new_array(type, nil, 0)
    }
    return children.withUnsafeBufferPointer { g_variant_new_array(nil, $0.baseAddress, gsize($0.count)) }
}

/// a{sv} from (key, value) pairs.
private func dictionary(_ entries: [(String, OpaquePointer)]) -> OpaquePointer {
    if entries.isEmpty {
        let type = g_variant_type_new("{sv}")
        defer { g_variant_type_free(type) }
        return g_variant_new_array(type, nil, 0)
    }
    let children = entries.map { (g_variant_new_dict_entry(string($0.0), g_variant_new_variant($0.1))) }
    return children.withUnsafeBufferPointer { g_variant_new_array(nil, $0.baseAddress, gsize($0.count)) }
}

private func tuple(_ children: [OpaquePointer]) -> OpaquePointer {
    let items = children.map { Optional($0) }
    return items.withUnsafeBufferPointer { g_variant_new_tuple($0.baseAddress, gsize($0.count)) }
}

final class MPRISServer {
    nonisolated(unsafe) static let shared = MPRISServer()

    private var started = false
    private var connection: OpaquePointer?
    private var nodeInfo: UnsafeMutablePointer<GDBusNodeInfo>?
    /// Last values sent, to signal only what changed (GVariants, owned).
    private var published: [String: OpaquePointer] = [:]
    private var trackNumber = 0
    private var trackKey = ""
    private var artImage: NSImage?
    private var artURL: URL?
    private var artNumber = 0

    private var info: MPNowPlayingInfoCenter { .default() }
    private var commands: MPRemoteCommandCenter { .current }

    func start() {
        guard !started else { return }
        started = true
        nodeInfo = g_dbus_node_info_new_for_xml(introspection, nil)
        let name = "org.mpris.MediaPlayer2.voidplay"
        g_bus_own_name(G_BUS_TYPE_SESSION, name, GBusNameOwnerFlags(rawValue: 0), { connection, _, _ in
            MPRISServer.shared.register(on: connection)
        }, nil, { connection, name, _ in
            NSLog("MPRIS: could not own %@%@", String(cString: name!), connection == nil ? " (no session bus)" : "")
        }, nil, nil)
    }

    private func register(on connection: OpaquePointer?) {
        guard let connection, let nodeInfo else { return }
        self.connection = connection
        var vtable = GDBusInterfaceVTable()
        vtable.method_call = { _, _, _, interface, method, parameters, invocation, _ in
            MPRISServer.shared.call(String(cString: interface!), String(cString: method!), parameters, invocation)
        }
        vtable.get_property = { _, _, _, interface, property, _, _ in
            MPRISServer.shared.property(String(cString: interface!), String(cString: property!))
        }
        vtable.set_property = { _, _, _, _, _, _, _, _ in 1 }  // Rate and Volume: accepted, ignored
        for name in [rootInterface, playerInterface] {
            var error: UnsafeMutablePointer<GError>?
            let id = g_dbus_connection_register_object(connection, objectPath,
                                                       g_dbus_node_info_lookup_interface(nodeInfo, name),
                                                       &vtable, nil, nil, &error)
            if id == 0, let error {
                NSLog("MPRIS: registering %@ failed: %@", name, String(cString: error.pointee.message))
                g_error_free(error)
            }
        }
        snapshotPlayerProperties()
    }

    // MARK: Methods

    private func call(_ interface: String, _ method: String, _ parameters: OpaquePointer?, _ invocation: OpaquePointer?) {
        switch (interface, method) {
        case (rootInterface, "Quit"):
            // Reply first: terminating inside the call would leave the caller with NoReply.
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        case (rootInterface, "Raise"): break
        case (_, "Play"): commands.playCommand.send()
        case (_, "Pause"): commands.pauseCommand.send()
        case (_, "PlayPause"): commands.togglePlayPauseCommand.send()
        case (_, "Next"): commands.nextTrackCommand.send()
        case (_, "Previous"): commands.previousTrackCommand.send()
        case (_, "Stop"):
            // NowPlayingManager registers no stop command; pausing is the closest it offers.
            if !commands.stopCommand.send() { commands.pauseCommand.send() }
        case (_, "Seek"):
            seek(to: max(0, info.currentElapsed + Double(int64(parameters, 0)) / 1e6))
        case (_, "SetPosition"):
            let child = g_variant_get_child_value(parameters, 0)
            let track = String(cString: g_variant_get_string(child, nil))
            g_variant_unref(child)
            if track == trackID { seek(to: Double(int64(parameters, 1)) / 1e6) }
        default: break  // OpenUri: no URI schemes advertised
        }
        g_dbus_method_invocation_return_value(invocation, nil)
    }

    private func int64(_ parameters: OpaquePointer?, _ index: Int) -> Int64 {
        let child = g_variant_get_child_value(parameters, gsize(index))
        defer { g_variant_unref(child) }
        return Int64(g_variant_get_int64(child))
    }

    private func seek(to position: TimeInterval) {
        let command = commands.changePlaybackPositionCommand
        command.send(MPChangePlaybackPositionCommandEvent(command: command, positionTime: position))
    }

    // MARK: Properties

    private var trackID: String { "/org/voidplay/track/\(trackNumber)" }

    private var playbackStatus: String {
        switch info.playbackState {
        case .playing: return "Playing"
        case .paused, .interrupted: return "Paused"
        case .stopped, .unknown: return info.nowPlayingInfo == nil ? "Stopped" : "Paused"
        }
    }

    private func metadata() -> OpaquePointer {
        guard let now = info.nowPlayingInfo else { return dictionary([]) }
        let title = now[MPMediaItemPropertyTitle] as? String ?? ""
        let artist = now[MPMediaItemPropertyArtist] as? String
        let album = now[MPMediaItemPropertyAlbumTitle] as? String
        let duration = (now[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue
        let key = [title, artist ?? "", album ?? ""].joined(separator: "\u{1}")
        if key != trackKey { trackKey = key; trackNumber += 1 }

        var entries: [(String, OpaquePointer)] = [("mpris:trackid", g_variant_new_object_path(trackID)),
                                                  ("xesam:title", string(title))]
        if let artist { entries.append(("xesam:artist", stringArray([artist]))) }
        if let album { entries.append(("xesam:album", string(album))) }
        if let duration, duration > 0 { entries.append(("mpris:length", g_variant_new_int64(gint64(duration * 1e6)))) }
        if let url = artworkURL(now[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork) {
            entries.append(("mpris:artUrl", string(url.absoluteString)))
        }
        return dictionary(entries)
    }

    /// Cover written to a file for clients (art URLs must be URIs); a new name per image so they reload.
    private func artworkURL(_ artwork: MPMediaItemArtwork?) -> URL? {
        guard let artwork, let image = artwork.image(at: artwork.bounds.size) else { return nil }
        if image === artImage { return artURL }
        if let old = artURL { try? FileManager.default.removeItem(at: old) }
        artImage = image
        artNumber += 1
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidplay-mpris-\(getpid())-\(artNumber).png")
        artURL = (try? image.tiffRepresentation?.write(to: url)) != nil ? url : nil
        return artURL
    }

    private func playerProperty(_ name: String) -> OpaquePointer? {
        let hasTrack = info.nowPlayingInfo != nil
        switch name {
        case "PlaybackStatus": return string(playbackStatus)
        case "LoopStatus": return string("None")
        case "Rate", "MinimumRate", "MaximumRate", "Volume": return g_variant_new_double(1)
        case "Shuffle": return g_variant_new_boolean(0)
        case "Metadata": return metadata()
        case "Position": return g_variant_new_int64(gint64(info.currentElapsed * 1e6))
        case "CanGoNext": return g_variant_new_boolean(commands.nextTrackCommand.isAvailable ? 1 : 0)
        case "CanGoPrevious": return g_variant_new_boolean(commands.previousTrackCommand.isAvailable ? 1 : 0)
        case "CanPlay": return g_variant_new_boolean(hasTrack && commands.playCommand.isAvailable ? 1 : 0)
        case "CanPause": return g_variant_new_boolean(hasTrack && commands.pauseCommand.isAvailable ? 1 : 0)
        case "CanSeek": return g_variant_new_boolean(hasTrack && commands.changePlaybackPositionCommand.isAvailable ? 1 : 0)
        case "CanControl": return g_variant_new_boolean(1)
        default: return nil
        }
    }

    private func property(_ interface: String, _ name: String) -> OpaquePointer? {
        guard interface == rootInterface else { return playerProperty(name) }
        switch name {
        case "CanQuit": return g_variant_new_boolean(1)
        case "CanRaise", "HasTrackList": return g_variant_new_boolean(0)
        case "Identity": return string("Voidplay")
        case "DesktopEntry": return string("voidplay")
        case "SupportedUriSchemes", "SupportedMimeTypes": return stringArray([])
        default: return nil
        }
    }

    // MARK: Change signals

    /// Player properties that announce changes (Position is polled, with Seeked for jumps).
    private static let signalled = ["PlaybackStatus", "Metadata", "CanGoNext", "CanGoPrevious", "CanPlay",
                                    "CanPause", "CanSeek"]

    @discardableResult
    private func snapshotPlayerProperties() -> [(String, OpaquePointer)] {
        var changed: [(String, OpaquePointer)] = []
        for name in Self.signalled {
            guard let value = playerProperty(name).map({ g_variant_ref_sink($0)! }) else { continue }
            if let old = published[name], g_variant_equal(UnsafeRawPointer(old), UnsafeRawPointer(value)) != 0 {
                g_variant_unref(value)
                continue
            }
            if let old = published[name] { g_variant_unref(old) }
            published[name] = value
            changed.append((name, value))
        }
        return changed
    }

    private var lastElapsed: (time: TimeInterval, at: Date)?

    func nowPlayingDidChange() {
        guard let connection else { return }
        let changed = snapshotPlayerProperties()
        if !changed.isEmpty {
            let body = tuple([string(playerInterface),
                              dictionary(changed),
                              stringArray([])])
            g_dbus_connection_emit_signal(connection, nil, objectPath, "org.freedesktop.DBus.Properties",
                                          "PropertiesChanged", body, nil)
        }
        // A jump the clients' own extrapolation would not predict is a seek.
        let elapsed = info.currentElapsed
        if let last = lastElapsed, !changed.contains(where: { $0.0 == "Metadata" }) {
            let expected = last.time + (info.playbackState == .playing ? Date().timeIntervalSince(last.at) : 0)
            if abs(elapsed - expected) > 1 {
                g_dbus_connection_emit_signal(connection, nil, objectPath, playerInterface, "Seeked",
                                              tuple([g_variant_new_int64(gint64(elapsed * 1e6))]), nil)
            }
        }
        lastElapsed = (elapsed, Date())
    }
}
