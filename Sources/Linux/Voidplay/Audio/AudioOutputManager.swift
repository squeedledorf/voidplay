import Foundation
import CoreAudio

/// An output device. Same shape as upstream's; on Linux `uid` is mpv's device name
/// (e.g. `pipewire/alsa_output.usb-…`) and `id` is a stable hash of it.
struct AudioOutputDevice: Equatable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isWireless: Bool
    let isAirPlayDiscovered: Bool

    init(id: AudioDeviceID, uid: String, name: String, isWireless: Bool, isAirPlayDiscovered: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isWireless = isWireless
        self.isAirPlayDiscovered = isAirPlayDiscovered
    }

    static func == (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool { lhs.uid == rhs.uid }
    func hash(into hasher: inout Hasher) { hasher.combine(uid) }
}

/// Output devices as libmpv sees them (PipeWire, PulseAudio, ALSA).
final class AudioOutputManager {
    static let shared = AudioOutputManager()
    static let devicesDidChangeNotification = Notification.Name("AudioOutputDevicesDidChange")

    private(set) var currentDeviceID: AudioDeviceID?

    /// A silent mpv instance just for enumeration, so listing works before any engine exists.
    private lazy var lister = MpvPlayer(options: ["vid": "no", "idle": "yes", "terminal": "no", "msg-level": "all=no"])

    var outputDevices: [AudioOutputDevice] {
        let list = lister?.node("audio-device-list") as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let uid = entry["name"] as? String, uid != "auto" else { return nil }
            let name = entry["description"] as? String ?? uid
            return AudioOutputDevice(id: Self.deviceID(for: uid), uid: uid, name: name,
                                     isWireless: uid.contains("bluez"))
        }
    }

    func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        outputDevices.first { $0.id == deviceID }?.name
    }

    func getDefaultOutputDeviceID() -> AudioDeviceID? { nil }

    var currentDeviceDisplayName: String {
        currentDeviceID.flatMap(getDeviceName) ?? "System Default"
    }

    func mpvDeviceName(for deviceID: AudioDeviceID) -> String? {
        let uid = outputDevices.first { $0.id == deviceID }?.uid
        if uid != nil { currentDeviceID = deviceID }
        return uid
    }

    /// FNV-1a, so a device keeps its id across runs and list reorders.
    private static func deviceID(for uid: String) -> AudioDeviceID {
        var hash: UInt32 = 2_166_136_261
        for byte in uid.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash == 0 ? 1 : hash
    }
}
