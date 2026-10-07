import Foundation
import GRDB

/// How many episodes each season of a series holds.
public extension LibraryRepository {

    /// season id → cached episode count, in one query.
    ///
    /// The server does not answer this. Jellyfin reports `ChildCount` only when the
    /// request asks for a field the sync does not use, so every one of the 3,221
    /// season rows in this cache has it NULL — which is why the count is taken from
    /// the episodes actually cached rather than read off the season.
    ///
    /// That makes it a count of what *this app* holds, and on a fully synced library
    /// those are the same number. A season still syncing reads low for a moment and
    /// then corrects itself, which is the honest thing for it to do: it is the count
    /// of episodes the strip above will actually show you.
    func episodeCounts(seriesId: String) async throws -> [String: Int] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT parentId, count(*) AS n FROM item
                    WHERE type = 'Episode' AND seriesId = ? AND parentId IS NOT NULL
                    GROUP BY parentId
                    """,
                arguments: [seriesId]
            )
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let id: String = row["parentId"], let n: Int = row["n"] else { return nil }
                return (id, n)
            })
        }
    }
}
