import Foundation

/// The reasons a library needs a full read rather than an incremental one.
///
/// Pure, so the rule that decides a two-hundred-request pass against a
/// two-request one can be tested without a server.
public enum SyncTrigger {

    /// Whether the server rewrote rows after this client last read them all.
    ///
    /// `repairedAt` is the server's RFC 3339 stamp, or nil where the server
    /// does not say (Jellyfin never does). A stamp the client cannot parse is
    /// treated as no stamp — a full sync on every launch would be the wrong
    /// price for a malformed date.
    public static func repairedSince(lastFull: Date?, repairedAt: String?) -> Bool {
        guard let repairedAt, let repaired = parse(repairedAt) else { return false }
        guard let lastFull else { return true }
        return repaired > lastFull
    }

    private static func parse(_ stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }
}
