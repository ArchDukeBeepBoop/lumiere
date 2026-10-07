import Foundation
import CryptoKit

/// Folders on this Mac, browsed and played as a library of their own.
///
/// Lumiere is a Jellyfin client, and for a long time that meant a server was the
/// only way in: media sitting on the machine running the app could not be opened
/// at all without first being catalogued by something else. This is the answer —
/// point Lumiere at a folder and it is a library.
///
/// **The design decision worth defending.** A local folder is not modelled as a
/// separate world with its own browser, its own player and its own watch state. It
/// is written into the same cache as everything else, as ordinary `ItemRecord`
/// rows under a synthetic server. Everything the app already does then works on it
/// for free and, more importantly, *keeps* working: the folder browser, filename
/// titles, generated thumbnails, favourites, watch state, search, the A–Z rail,
/// the player and its subtitle handling were all built once. A parallel
/// implementation would have been a second-class copy of each, drifting from the
/// first with every change.
///
/// The cost is honest and small: rows carry a `serverId` of `local`, and the sync
/// that talks to Jellyfin has to leave them alone. That is one condition, in one
/// place, rather than a duplicate of the app.
public enum LocalLibrary {

    /// The synthetic server every local row belongs to. Nothing that talks to
    /// Jellyfin may touch a row carrying it.
    public static let serverId = "local"

    /// What counts as playable. Deliberately generous — mpv opens essentially
    /// anything, and a file left out of the list is invisible with no explanation,
    /// which is worse than one that fails to play with a message.
    public static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "wmv", "flv", "webm", "mpg", "mpeg",
        "m2ts", "ts", "mts", "vob", "ogv", "rmvb", "divx", "asf", "3gp", "m2v"
    ]

    /// One spelling of a path, whichever way you arrived at it.
    ///
    /// macOS hands out two names for the same file constantly: `/var/...` and
    /// `/private/var/...`, `/tmp` and `/private/tmp`, a home directory reached
    /// through a symlink, an aliased volume. `contentsOfDirectory` returns the
    /// resolved form while a URL you built by appending components keeps the
    /// unresolved one — so a folder's own row and the rows inside it were being
    /// hashed from two different strings, giving two different ids for one file.
    ///
    /// The visible symptom was Rescan reporting that a folder's location was no
    /// longer recorded, because the reverse lookup hashes a stored path and
    /// compares it against the id built from the path you chose. Resolving once,
    /// here, is what makes "the same file always has the same id" true rather
    /// than merely intended.
    public static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// A stable id for a path.
    ///
    /// Derived from the path rather than allocated, so re-scanning a folder finds
    /// the same rows and everything keyed to them — watch state, favourites, a
    /// subtitle offset, a generated thumbnail — survives. A random id would reset
    /// all of it on every scan, which is the failure that makes local libraries in
    /// other players feel disposable.
    ///
    /// Hashed rather than using the path itself, because the id is a primary key
    /// that ends up in URLs, log lines and joins, and a path can be any length and
    /// contain anything.
    public static func id(for path: String) -> String {
        let digest = SHA256.hash(data: Data(canonicalPath(path).utf8))
        return "local:" + digest.map { String(format: "%02x", $0) }.prefix(16).joined()
    }

    /// The library id for a chosen root folder.
    public static func libraryId(for path: String) -> String {
        "locallib:" + id(for: path).dropFirst("local:".count)
    }

    public static func isLocal(itemId: String) -> Bool {
        itemId.hasPrefix("local:")
    }
}
