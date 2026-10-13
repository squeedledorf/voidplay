import Foundation

/// How Voidplay names itself to people and to servers. The licence (GPL-3.0 §7(e) term) bars
/// forks from presenting as NullPlayer, so every user-facing product name reads from here.
enum ClientIdentity {
    static let productName = "Voidplay"
    /// Executable name, as typed in a terminal.
    static let commandName = "voidplay"
    /// Folder under Application Support / $XDG_DATA_HOME holding the library and history databases.
    static let dataDirectoryName = "Voidplay"
    /// Platform reported to media servers (Plex X-Plex-Device, Jellyfin/Emby Device).
    #if os(Linux)
    static let deviceKind = "Linux"
    #else
    static let deviceKind = "Mac"
    #endif
}
