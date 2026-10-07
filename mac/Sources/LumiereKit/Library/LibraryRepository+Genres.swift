import Foundation
import GRDB

/// One genre and how much is actually behind it.
public struct GenreTally: Sendable, Hashable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public extension LibraryRepository {

    // MARK: - Matching one genre

    /// The predicate that decides whether a row carries a genre.
    ///
    /// `genres` is a newline-joined string, and the filter used to be
    /// `genres LIKE '%Comedy%'` — a substring test that knows nothing about where
    /// one genre ends and the next begins. On TMDB's own vocabulary that
    /// over-matches constantly: "Action" matches every "Action & Adventure" show,
    /// "Fantasy" matches "Sci-Fi & Fantasy", "War" matches "War & Politics",
    /// "Music" matches "Musical". So the counts were inflated and a genre page
    /// showed titles that are not in that genre.
    ///
    /// Wrapping both the column and the needle in newlines turns the same LIKE
    /// into a whole-element test: `\nComedy\n` can only land on a complete entry.
    /// NULL propagates through the concatenation, so an item with no genres is
    /// excluded without a second predicate.
    static let genreMatchSQL =
        #"(CHAR(10) || item.genres || CHAR(10)) LIKE ? ESCAPE '\'"#

    /// The needle for `genreMatchSQL`.
    ///
    /// Escaped, because a genre is a name from someone's server rather than a
    /// literal: LIKE reads `%` and `_` as wildcards, so an unescaped genre
    /// containing either would silently match the wrong rows.
    static func genrePattern(_ genre: String) -> String {
        var escaped = ""
        for character in genre {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "%\n\(escaped)\n%"
    }

    // MARK: - The catalogue

    /// Every genre present, with an exact count, in one pass.
    ///
    /// One query rather than the catalogue-plus-a-count-per-genre it replaces:
    /// building ten cards used to mean a full scan for the names followed by ten
    /// more `COUNT(*)` queries, and offering more cards meant more queries. Here
    /// the split happens once in Swift over a single column, so the cost is the
    /// same whether the row shows ten genres or fifty.
    ///
    /// Carries the same exclusions as `entries` and `count` — no extras, no
    /// hidden collections — so a card's number and the page it opens agree.
    func genreTallies(
        types: [JellyfinItem.ItemType] = [],
        libraryId: String? = nil
    ) async throws -> [GenreTally] {
        // Read before the block: `privacyFilter` is actor state, and the read
        // closure is not on the actor.
        let privacy = libraryId == nil ? privacyFilter() : nil

        let rows: [String] = try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                .filter(Column("genres") != nil)
            if let privacy { request = request.filter(sql: privacy) }
            if let libraryId { request = request.filter(Column("libraryId") == libraryId) }
            if !types.isEmpty {
                request = request.filter(types.map(\.rawValue).contains(Column("type")))
            }
            return try String.fetchAll(db, request.select(Column("genres")))
        }

        var counts: [String: Int] = [:]
        for row in rows {
            // Deduplicated per item, so a row that somehow lists a genre twice
            // still counts once — which is what the SQL count would say.
            for genre in Set(row.components(separatedBy: "\n")) where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }

        // Biggest first, ties broken by name so the order is stable between runs
        // rather than dictionary order.
        return counts
            .map { GenreTally(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
