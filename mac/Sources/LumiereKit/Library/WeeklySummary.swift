import Foundation

/// A once-a-week line on what changed in the library.
///
/// Library Health answers when asked, and the dot on Settings when something
/// grows; this is the other half — the good news and the slow drift together,
/// once a week, so neither has to be gone looking for.
public enum WeeklySummary {

    public static let storageKey = "weeklySummary"

    /// What was counted last time: health kinds by count, plus "subtitlesDone".
    public struct Snapshot: Codable, Sendable, Equatable {
        public var at: Date
        public var counts: [String: Int]
        public init(at: Date, counts: [String: Int]) { self.at = at; self.counts = counts }
    }

    /// Whether a week has passed since the last summary (or there was none).
    public static func isDue(last: Snapshot?, now: Date = Date()) -> Bool {
        guard let last else { return false }   // first run: a baseline, not news
        return now.timeIntervalSince(last.at) >= 7 * 24 * 3600
    }

    /// The sentence, or nil when nothing changed worth saying.
    public static func message(from last: Snapshot, to now: Snapshot) -> String? {
        var parts: [String] = []
        let fetched = (now.counts["subtitlesDone"] ?? 0) - (last.counts["subtitlesDone"] ?? 0)
        if fetched > 0 { parts.append("\(fetched) subtitle\(fetched == 1 ? "" : "s") fetched") }
        let labels = ["Unreadable": "unreadable file", "EmptySeries": "empty show",
                      "MissingEpisodes": "missing episode", "DuplicateFilms": "duplicated film",
                      "EmptyCollections": "empty collection", "DuplicateCollections": "repeated collection",
                      "MismatchedShows": "wrongly matched show"]
        for (kind, label) in labels.sorted(by: { $0.key < $1.key }) {
            let change = (now.counts[kind] ?? 0) - (last.counts[kind] ?? 0)
            if change > 0 { parts.append("\(change) new \(label)\(change == 1 ? "" : "s")") }
            if change < 0 { parts.append("\(-change) \(label)\(change == -1 ? "" : "s") fixed") }
        }
        guard !parts.isEmpty else { return nil }
        return "This week: " + parts.joined(separator: ", ") + "."
    }
}
