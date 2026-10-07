import Foundation
import GRDB

/// Where each letter starts in a library, for the jump rail.
public struct AlphabetAnchor: Sendable, Hashable {
    public let letter: String
    /// The first item filed under it.
    public let id: String
    /// How many rows precede it under the current sort — which is what turns a
    /// letter into "load this far, then scroll".
    public let offset: Int
}

public extension LibraryRepository {

    /// The first row under each letter, across the *whole* library.
    ///
    /// This exists because the obvious implementation is wrong in a way that looks
    /// almost right. Building the rail from the rows a grid has loaded means it only
    /// knows the first page: on a library of four thousand, every letter past "B"
    /// pointed at nothing, and the letters came alive one by one as paging happened
    /// to reach them — which is why scrolling to the bottom appeared to "fix" it.
    /// The rail has to be built from the library, not from the window onto it.
    ///
    /// Reads two columns rather than whole rows: an anchor needs an id and a sort
    /// key, and pulling `LibraryEntry` for 24,000 items to derive 27 answers would
    /// cost more than the grid it serves.
    func alphabetAnchors(
        libraryId: String?,
        types: [JellyfinItem.ItemType] = [],
        sort: Sort = .title,
        genre: String? = nil,
        studio: String? = nil,
        searchTerm: String? = nil,
        unwatchedOnly: Bool = false
    ) async throws -> [AlphabetAnchor] {
        // Only meaningful in name order. In date-added order the letters are
        // scattered through the list, and jumping to "S" would land somewhere
        // arbitrary — so the caller hides the rail rather than this lying about it.
        guard sort == .title else { return [] }

        struct Row: Decodable, FetchableRecord {
            let id: String
            let sortName: String
        }

        // Every filter the grid applies, applied here too.
        //
        // An anchor's `offset` is "how many rows precede this letter", and the grid
        // scrolls to it. It was computed over a *different* row set: no search term,
        // no unwatched filter, no hidden collections, no privacy. So with Unwatched
        // on, or a search active, every letter jump landed short — and the further
        // down the alphabet, the worse the error. A rail that points at the wrong
        // row is worse than no rail, because it looks like it worked.
        let privacy = libraryId == nil ? privacyFilter() : nil

        let rows: [Row] = try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .select(Column("id"), Column("sortName"))
                .filter(Column("serverId") == serverId)
                .filter(Column("extraType") == nil)
                .order(Column("sortName").asc)

            if let libraryId { request = request.filter(Column("libraryId") == libraryId) }
            if !types.isEmpty {
                request = request.filter(types.map(\.rawValue).contains(Column("type")))
            }
            if let privacy { request = request.filter(sql: privacy) }
            request = request.filter(sql: HiddenCollections.filterSQL)
            if unwatchedOnly {
                request = request.filter(sql:
                    "NOT EXISTS (SELECT 1 FROM userData "
                  + "WHERE userData.itemId = item.id AND userData.played = 1)")
            }
            if let searchTerm, !searchTerm.isEmpty {
                // Token-by-token against the normalised key, exactly as `entries`
                // builds it — the same helper, so the two cannot drift.
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

            return try Row.fetchAll(db, request)
        }

        var anchors: [AlphabetAnchor] = []
        var seen: Set<String> = []
        for (offset, row) in rows.enumerated() {
            let letter = AlphabetIndex.letter(forSortKey: row.sortName)
            guard !seen.contains(letter) else { continue }
            seen.insert(letter)
            anchors.append(AlphabetAnchor(letter: letter, id: row.id, offset: offset))
        }
        return anchors
    }
}
