import Foundation

/// When a cached detail payload is worth asking the server about again.
///
/// Pure, so the rule can be tested without a database.
public enum DetailFreshness {

    /// Whether a payload with no cast has sat long enough to look again.
    ///
    /// A film, show or episode the server matched will get its credits from
    /// the naming pass a minute or two after it arrives; a payload cached in
    /// that window has an empty Cast & Crew row and a day to live. Anything
    /// else — a folder, a season, a loose video — has no cast to wait for.
    public static func isStaleWithoutCredits(_ item: JellyfinItem, fetchedAt: Date, now: Date) -> Bool {
        guard [.movie, .series, .episode].contains(item.type) else { return false }
        guard (item.people ?? []).isEmpty else { return false }
        return now.timeIntervalSince(fetchedAt) >= LibraryRepository.uncreditedFreshness
    }
}
