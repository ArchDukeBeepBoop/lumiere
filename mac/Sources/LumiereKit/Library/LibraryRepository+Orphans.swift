import Foundation
import GRDB

extension LibraryRepository {
    /// Stamps the library onto rows that arrived by some other route.
    ///
    /// Collection members, Next Up entries, similar titles and server search results
    /// are all cached without a libraryId, because only a library sync knows which
    /// library it is reading. Those rows were invisible to every grid *and* immune
    /// to the deletion sweep, which filters on libraryId — 3,267 of them on a real
    /// library, permanent whatever happened on the server. Anything a pass saw
    /// belongs to that library by definition.
    ///
    /// Chunked because SQLite has a bound-parameter limit, and a library sync sees
    /// tens of thousands of ids.
    func adoptOrphanedRows(seenIds: Set<String>, libraryId: String) async {
        guard !seenIds.isEmpty else { return }
        let ids = Array(seenIds)

        try? await database.writer.write { db in
            for chunk in stride(from: 0, to: ids.count, by: 500) {
                let slice = Array(ids[chunk..<min(chunk + 500, ids.count)])
                let placeholders = slice.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "UPDATE item SET libraryId = ? "
                       + "WHERE libraryId IS NULL AND id IN (\(placeholders))",
                    arguments: StatementArguments([libraryId] + slice)
                )
            }
        }
    }

    /// Deletes cached rows that no sync can ever reach, and that nothing reads.
    ///
    /// The library sweep in `syncLibrary` matches on `libraryId`, so a row with none
    /// is invisible to it — permanently, however many full syncs run. `adoptOrphanedRows`
    /// above closes that gap for anything a library pass actually saw, and on a real
    /// library it left 3,234 rows behind that no pass ever will:
    ///
    /// - 3,204 music and playlist rows (MusicArtist, MusicAlbum, Audio). Music is
    ///   never synced — `LibraryRepository+MusicPaging` says why, and every screen of
    ///   it is a live request — so these are written only so `entriesById` can join
    ///   watch state onto a page that has already arrived. Nothing ever reads them
    ///   back. 1,181 of them pointed at files that no longer exist on disk, some
    ///   cached a week earlier, and they leaked into the places that *don't* filter
    ///   on `libraryId`: search, `resumeEntries`, favourites, `folderChildren`. With
    ///   no artwork tag — 469 of them had none — a poster request resolves to nothing
    ///   and the tile draws empty, which is the "deleted files show up as an empty
    ///   poster" report.
    /// - 27 extras, which are legitimate: they are cached deliberately by
    ///   `extras(itemId:)` so a detail page seen once still lists them offline, and
    ///   they are excluded below.
    ///
    /// Three guards, each earning its place. Extras are kept because something reads
    /// them. Anything carrying history — played, starred, part-watched, downloaded,
    /// ranked inside a collection, hidden from a shelf — is kept because losing that
    /// is unrecoverable and a stale row is not. And a row cached in the last hour is
    /// kept because the music browser may be looking at it right now.
    ///
    /// Returns how many went, for the log.
    @discardableResult
    public func pruneUnreachableRows(cachedBefore cutoff: Date) async -> Int {
        (try? await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM userData WHERE itemId IN (
                        SELECT id FROM item
                        WHERE libraryId IS NULL AND extraType IS NULL AND syncedAt < ?
                    )
                    AND played = 0 AND isFavorite = 0 AND playbackPositionTicks = 0
                    -- playCount belongs with the rest, and its absence was a hole
                    -- in the promise the comment above makes. Jellyfin's
                    -- "mark unwatched" zeroes `played` and the resume position but
                    -- leaves the count, so a row watched and later un-marked looked
                    -- exactly like one that was never touched — and was erased on
                    -- the next launch. Nine rows are in that state on this library.
                    AND playCount = 0
                    """,
                arguments: [cutoff]
            )
            try db.execute(
                sql: """
                    DELETE FROM item
                    WHERE libraryId IS NULL
                      AND extraType IS NULL
                      AND syncedAt < ?
                      AND id NOT IN (SELECT itemId FROM userData)
                      AND id NOT IN (SELECT itemId FROM download)
                      AND id NOT IN (SELECT itemId FROM collectionRank)
                      AND id NOT IN (SELECT itemId FROM hiddenShelfItem)
                    """,
                arguments: [cutoff]
            )
            return db.changesCount
        }) ?? 0
    }
}
