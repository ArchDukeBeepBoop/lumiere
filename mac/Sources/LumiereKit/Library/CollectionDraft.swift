import Foundation

/// The details a newly built collection should start with, derived from what it
/// holds.
///
/// A collection created from a scan arrives named after the key that found it —
/// "Monogatari", "Fate" — with no year, no synopsis and no artwork. Filling those
/// in by hand for every franchise is the work this whole feature exists to remove,
/// and doing it badly is worse than leaving it blank: a wrong year on a collection
/// is a wrong year on a shelf.
///
/// So every suggestion here comes from the members themselves and is offered rather
/// than applied. Pure, so the derivation is testable without a server.
public enum CollectionDraft {

    public struct Suggestion: Sendable, Equatable {
        public var name: String
        /// The year the franchise *started*, which is what a collection's date
        /// means — not the newest entry, and not an average of anything.
        public var year: Int?
        public var overview: String
        /// Which member the synopsis came from, so the sheet can say so. A borrowed
        /// paragraph presented as the collection's own is a small lie that reads
        /// badly once you notice it.
        public var overviewSource: String?

        public init(name: String, year: Int?, overview: String, overviewSource: String?) {
            self.name = name
            self.year = year
            self.overview = overview
            self.overviewSource = overviewSource
        }
    }

    /// Builds the starting point for a collection called `name` holding `members`.
    public static func suggest(name: String, members: [LibraryEntry]) -> Suggestion {
        Suggestion(
            name: displayName(name),
            year: members.compactMap { $0.item.productionYear }.min(),
            overview: overview(from: members) ?? "",
            overviewSource: overviewMember(from: members)?.item.name
        )
    }

    /// The synopsis of the earliest entry that has one.
    ///
    /// The first entry's synopsis describes the premise the rest of the franchise
    /// is built on, which is the closest thing to a description of the whole. The
    /// longest one would more often be a sequel's recap — three paragraphs assuming
    /// you have seen the first, which is exactly wrong at the top of a collection.
    static func overviewMember(from members: [LibraryEntry]) -> LibraryEntry? {
        members
            .filter { !($0.item.overview ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .min { left, right in
                switch (left.item.productionYear, right.item.productionYear) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil):
                    return left.item.name.localizedStandardCompare(right.item.name)
                        == .orderedAscending
                }
            }
    }

    private static func overview(from members: [LibraryEntry]) -> String? {
        overviewMember(from: members)?.item.overview
    }

    /// Tidies a key into something worth putting on a shelf.
    ///
    /// The keys arrive lowercased from a tag or assembled from a filename stem, and
    /// a franchise called "monogatari" looks like a bug rather than a decision.
    public static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        guard trimmed == trimmed.lowercased() else { return trimmed }
        return trimmed
            .split(separator: " ")
            .map { $0.count <= 2 ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Whether a collection still needs a poster, which decides whether the wizard
    /// stops on it or moves on.
    public static func needsArtwork(_ entry: LibraryEntry?) -> Bool {
        guard let entry else { return true }
        return entry.item.primaryTag == nil
    }
}
