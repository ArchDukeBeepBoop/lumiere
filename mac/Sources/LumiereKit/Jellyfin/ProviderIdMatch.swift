import Foundation

/// Whether an item carries a provider id that was just applied.
///
/// Pure, because it decides something consequential on a guess: after the identify
/// endpoint drops the connection mid-scrape, this is what says whether the work
/// landed. Getting it wrong in one direction reports a successful identify as a
/// network failure — the bug it exists to fix — and in the other claims a failed one
/// worked.
///
/// Compared case-insensitively on both key and value. Providers are inconsistent
/// about it: Jellyfin stores "Tmdb" where a search result says "TMDB", and the ids
/// themselves are hex strings for some providers, so an exact match would report a
/// perfectly good identify as failed.
public enum ProviderIdMatch {

    public static func matches(
        expected: [String: String], actual: [String: String]
    ) -> Bool {
        guard !expected.isEmpty, !actual.isEmpty else { return false }

        let normalized = Dictionary(
            actual.map { ($0.key.lowercased(), $0.value.lowercased()) },
            // Two keys differing only in case are the same provider; either value
            // will do, and crashing on the collision would be a poor trade.
            uniquingKeysWith: { first, _ in first }
        )
        // Any, not all. A server that matched on TMDB may not have found the item on
        // TVDB at all, and requiring every id would call that a failure.
        return expected.contains { key, value in
            normalized[key.lowercased()] == value.lowercased()
        }
    }

    /// Pulls the ids out of a raw item payload, which is where they have to be read
    /// from — `JellyfinItem` does not decode them.
    public static func providerIds(in object: [String: Any]) -> [String: String] {
        guard let ids = object["ProviderIds"] as? [String: Any] else { return [:] }
        return Dictionary(
            ids.compactMap { key, value in (value as? String).map { (key, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
