import Foundation

/// Which way a show's picture is flipped, remembered per show.
///
/// A flip is a property of how a show was captured — a mirrored rip, a
/// camera held upside down — so every episode wants the same one. Per show
/// rather than per file for exactly that reason (a film is its own show),
/// and the opposite of `SubtitleOffset`, which fixes one file's track.
///
/// Kept in preferences rather than the library database: it is a viewing
/// choice, like subtitle size, not a fact about the library.
public enum FlipMemory {

    public static let storageKey = "flipByTitle"

    /// The flip remembered for a show, or none.
    public static func flip(
        for titleId: String, in defaults: UserDefaults = .standard
    ) -> (horizontal: Bool, vertical: Bool) {
        let bits = (defaults.dictionary(forKey: storageKey)?[titleId] as? Int) ?? 0
        return (bits & 1 != 0, bits & 2 != 0)
    }

    /// Remembers a flip; an unflipped picture is forgotten rather than stored.
    public static func remember(
        horizontal: Bool, vertical: Bool, for titleId: String,
        in defaults: UserDefaults = .standard
    ) {
        var all = defaults.dictionary(forKey: storageKey) ?? [:]
        let bits = (horizontal ? 1 : 0) | (vertical ? 2 : 0)
        all[titleId] = bits == 0 ? nil : bits
        defaults.set(all, forKey: storageKey)
    }
}
