import Foundation

/// Reading and writing the home screen's running order.
///
/// Pure, so the merge rules below can be tested without a home screen — and they
/// need testing, because every one of them is a decision about what happens when
/// the stored order and the current library list disagree, which they will: a
/// library gets added, renamed, hidden, or removed while an order written months
/// ago still names it.
public enum HomeOrder {

    /// The preference key. One order for every layout that draws these sections.
    public static let storageKey = "homeSectionOrder"

    /// The sections switched off, by id, comma-separated.
    ///
    /// Separate from the order rather than encoded into it, so switching a row
    /// off and on again puts it back where it was. A private library's Latest
    /// row is the case: it belongs on the home screen for its owner and nowhere
    /// near it for anyone glancing over, and that is a decision about the row,
    /// not about the running order.
    public static let hiddenKey = "homeHiddenSections"

    public static func hidden(from stored: String?) -> Set<String> {
        Set((stored ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    public static func encodeHidden(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }

    /// The order the app has always drawn, and what an untouched install gets.
    ///
    /// The Latest rows come last, after the curated rows, and in the order the
    /// libraries themselves are given — which is the server's order until someone
    /// moves one.
    public static func defaultOrder(libraryIds: [String]) -> [HomeSection] {
        [
            // Up Next first, under the spotlight, as Apple TV opens: what you
            // are in the middle of before anything to browse. Finish the Season
            // and Forgotten stay beside the rows whose question they answer.
            .spotlight, .continueWatching, .finishSeason, .nextUp, .forgotten,
            .continueSeries, .becauseYouWatched, .quickLinks, .libraries, .genres, .recentlyAdded,
            .topFilms, .topSeries, .topAnime,
        ] + libraryIds.map { .latest(libraryId: $0) }
    }

    /// The order to draw, given what was stored and what exists now.
    ///
    /// Three rules, each answering a way the two can disagree:
    ///
    /// - **A stored section that no longer exists is dropped.** A removed library's
    ///   Latest row cannot be drawn, and keeping it would leave a gap that only
    ///   appears once and cannot be explained.
    /// - **A section missing from the stored order is inserted where it belongs,**
    ///   next to the section that precedes it by default — not appended. A newly
    ///   added library's row lands with the other Latest rows rather than after a
    ///   Top 10 the user deliberately moved to the bottom, and a section added in a
    ///   future version arrives in its intended place instead of at the end.
    /// - **Duplicates collapse to their first occurrence.** Preferences can be hand
    ///   edited, and a section drawn twice is worse than one drawn in the wrong place.
    /// The orders earlier versions stored without anyone arranging anything —
    /// saved on first launch, not chosen. One of these is followed to the new
    /// default; an order someone did arrange is not touched.
    static let formerDefaults: [[String]] = [
        ["spotlight", "quickLinks", "libraries", "continueWatching", "genres", "nextUp",
         "recentlyAdded", "topFilms", "topSeries", "topAnime"],
        ["spotlight", "quickLinks", "libraries", "continueWatching", "finishSeason", "genres",
         "nextUp", "forgotten", "continueSeries", "recentlyAdded", "topFilms", "topSeries", "topAnime"],
    ]

    static func isFormerDefault(_ stored: String) -> Bool {
        let fixed = stored.split(separator: ",").map(String.init).filter { !$0.hasPrefix("latest:") }
        return formerDefaults.contains(fixed)
    }

    public static func resolve(stored: String?, libraryIds: [String]) -> [HomeSection] {
        let fallback = defaultOrder(libraryIds: libraryIds)
        guard let stored, !stored.isEmpty, !isFormerDefault(stored) else { return fallback }

        let valid = Set(fallback)
        var seen: Set<HomeSection> = []
        var order = stored
            .split(separator: ",")
            .compactMap { HomeSection(id: String($0)) }
            .filter { valid.contains($0) && seen.insert($0).inserted }

        // Whatever the stored list never mentioned, put back where it would have
        // been. Walking the default order forwards means each insertion sees the
        // ones already restored ahead of it, so a run of new libraries stays in
        // its own order rather than arriving reversed.
        for (index, section) in fallback.enumerated() where !seen.contains(section) {
            let predecessor = fallback[..<index].last { order.contains($0) }
            if let predecessor, let at = order.firstIndex(of: predecessor) {
                order.insert(section, at: at + 1)
            } else {
                order.insert(section, at: 0)
            }
            seen.insert(section)
        }
        return order
    }

    /// The library list, in the order their rows appear on the home screen.
    ///
    /// So that the row of library posters, the sidebar and every other list of
    /// libraries agree with the shelves below them. Moving "Anime" above
    /// "Movies" in settings is a statement about which library matters more, and
    /// it read as arbitrary when the tiles above kept the server's order while
    /// the shelves took the user's.
    ///
    /// A library with no row of its own — one whose Latest shelf is not in the
    /// order at all — keeps its existing place relative to the others rather
    /// than being swept to the end: the sections say where the *named* ones go
    /// and nothing about the rest.
    public static func libraryOrder(stored: String?, libraryIds: [String]) -> [String] {
        var rank: [String: Int] = [:]
        for (index, section) in resolve(stored: stored, libraryIds: libraryIds).enumerated() {
            if case .latest(let libraryId) = section { rank[libraryId] = index }
        }
        // Paired with the original index so the sort is stable: Swift's is not,
        // and two libraries with no row would otherwise swap places at random
        // between launches.
        return libraryIds.enumerated()
            .sorted { left, right in
                let a = rank[left.element] ?? Int.max
                let b = rank[right.element] ?? Int.max
                return a == b ? left.offset < right.offset : a < b
            }
            .map(\.element)
    }

    public static func encode(_ sections: [HomeSection]) -> String {
        sections.map(\.id).joined(separator: ",")
    }

    /// Moves one section one place up or down, and hands back the new order.
    ///
    /// A function rather than something the view does with indices, because "up"
    /// at the top and "down" at the bottom are the cases a view gets wrong, and
    /// they are testable here.
    public static func moved(
        _ section: HomeSection, by offset: Int, in order: [HomeSection]
    ) -> [HomeSection] {
        guard let from = order.firstIndex(of: section) else { return order }
        let to = from + offset
        guard order.indices.contains(to) else { return order }
        var moved = order
        moved.remove(at: from)
        moved.insert(section, at: to)
        return moved
    }
}
