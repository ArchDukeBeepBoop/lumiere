import Foundation

/// What order search results come back in.
///
/// They came back alphabetically, truncated at 120. On a library of this size
/// that is not a ranking at all: typing "gundam" returned the 120
/// alphabetically-first titles containing the word, so an exact match sat
/// wherever the alphabet put it — and where more than 120 things matched, it
/// could fall outside the window entirely and never be shown.
///
/// Pure and separate from the query so the rule can be checked against the
/// cases that matter rather than inferred from a screenshot.
public enum SearchRanking {

    /// Higher is better. The bands are deliberately far apart: within a band the
    /// tie-breaks decide, but no amount of tie-breaking should lift a
    /// mid-word match above an exact title.
    public enum Band: Int, Sendable {
        case exactTitle = 5
        case titlePrefix = 4
        case wordPrefix = 3
        case containsInTitle = 2
        /// Matched only through the series name or an alternative title.
        case matchedElsewhere = 1
        case none = 0
    }

    public static func band(name: String, term: String) -> Band {
        let title = SearchKey.normalize(name)
        let needle = SearchKey.normalize(term)
        guard !needle.isEmpty, !title.isEmpty else { return .none }
        if title == needle { return .exactTitle }
        if title.hasPrefix(needle) { return .titlePrefix }
        // A word inside the title starting with the term: "sky" finds
        // "Sky Wizards Academy" at the front and "Blue Sky" here.
        if title.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
            return .wordPrefix
        }
        if title.contains(needle) { return .containsInTitle }
        return .matchedElsewhere
    }

    /// The order results are shown in.
    ///
    /// - Parameter kindWeight: how much the *kind* of thing breaks a tie. A
    ///   series and a film are what people search for; an episode is usually
    ///   noise unless it was named directly, so it sinks within its band rather
    ///   than being excluded — searching an episode title must still find it.
    public static func score(
        name: String, term: String, kindWeight: Int = 0
    ) -> Int {
        let band = band(name: name, term: term)
        guard band != .none else { return 0 }
        // Shorter titles first within a band: "Gundam" before "Gundam Build
        // Fighters Try Island Wars", because the shorter one is more likely to
        // be the thing that was meant.
        let brevity = max(0, 60 - min(60, name.count))
        return band.rawValue * 10_000 + kindWeight * 100 + brevity
    }

    /// "Alien Collection" → "Alien", for ranking a collection as its series.
    public static func bareCollectionName(_ name: String) -> String {
        let suffix = " collection"
        guard name.lowercased().hasSuffix(suffix) else { return name }
        return String(name.dropLast(suffix.count))
    }
}
