import Foundation
import GRDB

/// How many rows a query would return.
///
/// Split from LibraryRepository.swift for the project's 300-line limit. It shares
/// its filter vocabulary with `entries` deliberately and has to keep sharing it: a
/// header reading "412 items" over a filtered grid of nine is worse than no count.
public extension LibraryRepository {

    /// Counts under the same filters the grid is showing.
    ///
    /// Sharing the filter set matters: a header reading "412 items" over a
    /// filtered grid of nine is worse than no count at all.
    func count(
        parentId: String? = nil,
        types: [JellyfinItem.ItemType] = [],
        libraryId: String? = nil,
        searchTerm: String? = nil,
        genre: String? = nil,
        studio: String? = nil,
        unwatchedOnly: Bool = false
    ) async throws -> Int {
        // Counted in SQL, including the unwatched case. This used to fetch up to
        // 5,000 full rows and count them in Swift — every filter change on a large
        // library built thousands of LibraryEntry values, joined watch state to each,
        // and threw them all away to learn a single number. On the 24,000-item Anime
        // library that is the slowest thing the grid does.
        //
        // NOT EXISTS rather than a LEFT JOIN so no row is duplicated by the join, and
        // a missing userData row counts as unwatched — which it is.
        let privacy = (parentId == nil && libraryId == nil) ? privacyFilter() : nil

        return try await database.writer.read { [visibleServerIds] db in
            // Same extras exclusion as `entries`, so the header's count and the grid
            // below it agree.
            var request = ItemRecord
                .filter(visibleServerIds.contains(Column("serverId")))
                .filter(Column("extraType") == nil)
                // Same exclusion as `entries`, so a count cannot disagree with the
                // grid it labels.
                .filter(sql: HiddenCollections.filterSQL)
            if let parentId { request = request.filter(Column("parentId") == parentId) }
            if let libraryId { request = request.filter(Column("libraryId") == libraryId) }
            if let privacy { request = request.filter(sql: privacy) }
            if !types.isEmpty {
                request = request.filter(types.map(\.rawValue).contains(Column("type")))
            }
            if let searchTerm, !searchTerm.isEmpty {
                // Every word must appear, in any order and anywhere in the key.
                //
                // The old query was one contiguous `LIKE` on `name`, which failed
                // three ways at once: "fate zero" could not match Fate/Zero because
                // the slash is not a space, "academy sky" could not match Sky
                // Wizards Academy because a substring has to be in order, and an
                // episode could not be found by its show. All three are the same
                // fix — match tokens against a normalised key.
                //
                // AND rather than OR: any two-word query under OR returns most of
                // the library, which is a different kind of unhelpful.
                for token in SearchKey.tokens(in: searchTerm) {
                    request = request.filter(Column("searchKey").like("%\(token)%"))
                }
            }
            if let genre {
                // Whole-genre, not substring — see `LibraryRepository.genreMatchSQL`.
                request = request.filter(
                    sql: Self.genreMatchSQL, arguments: [Self.genrePattern(genre)]
                )
            }
            if let studio {
                request = request.filter(
                    sql: Self.studioMatchSQL, arguments: [Self.studioPattern(studio)]
                )
            }
            if unwatchedOnly {
                request = request.filter(
                    sql: "NOT EXISTS (SELECT 1 FROM userData WHERE userData.itemId = item.id AND userData.played = 1)"
                )
            }
            return try request.fetchCount(db)
        }
    }
}
