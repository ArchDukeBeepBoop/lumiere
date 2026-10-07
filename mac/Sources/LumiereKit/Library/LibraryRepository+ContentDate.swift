import Foundation
import GRDB

/// Keeping each series' "newest episode" date current.
///
/// See the `v18_content_date` migration for why this is a stored column. In short:
/// Jellyfin stamps a Series row with when its *folder* was scanned, so a library
/// rescan makes every show in it look newly added while the episodes inside are
/// years old — and a Latest shelf ranked on that shows six shows from a rescan and
/// stops changing. Ranking a series by its newest episode is what "latest" means on
/// a TV library, and the correlated subquery that would compute it per sort did not
/// finish in five minutes over 45,000 rows.
extension LibraryRepository {

    /// Recomputes `contentDate` for the series of one library.
    ///
    /// Run at the end of that library's sync, where it is one indexed lookup per
    /// series — 737 of them here — rather than one per row being sorted.
    ///
    /// Only series are touched. Every other row's content date is its own creation
    /// date, written when the row is saved, and a film has nothing under it that
    /// could be newer than itself.
    public func refreshContentDates(libraryId: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE item SET contentDate = COALESCE(
                        (SELECT max(e.dateCreated) FROM item e
                          WHERE e.seriesId = item.id AND e.type = 'Episode'),
                        dateCreated
                    )
                    WHERE type = 'Series' AND libraryId = ?
                    """,
                arguments: [libraryId]
            )
        }
    }
}
