import Foundation
import GRDB

/// Pulling the *list* of libraries, as distinct from the items inside one.
///
/// Split from LibraryRepository+Sync.swift for the project's 300-line limit. It is
/// a genuinely separate pass: cheap, run on every launch, and the one thing a sync
/// cannot proceed without — a failure here is fatal to the whole sync, where a
/// failure reading one library is not.
extension LibraryRepository {

    /// Pulls the user's libraries. Cheap, so it runs on every launch.
    @discardableResult
    public func syncLibraries() async throws -> [LibraryRecord] {
        let views = try await client.userViews()
        let records = views.enumerated().map { index, view in
            LibraryRecord(from: view, serverId: serverId, sortIndex: index)
        }

        try await database.writer.write { [serverId] db in
            // Libraries the user no longer has access to must disappear, so this
            // is a replace rather than an upsert.
            try LibraryRecord
                .filter(Column("serverId") == serverId)
                .deleteAll(db)
            for record in records {
                try record.insert(db)
            }
        }

        // Here rather than in `syncLibrary`, because what it clears belongs to no
        // library — that is the whole reason no library sweep can reach it. Once per
        // launch is the right cadence: those rows accumulate from browsing, not from
        // syncing, so tying this to a library pass would be both too often and, on a
        // machine that only ever browses music, never.
        let pruned = await pruneUnreachableRows(cachedBefore: Date().addingTimeInterval(-3600))
        if pruned > 0 {
            Diagnostics.log("[sync] pruned \(pruned) rows no library sweep can reach")
        }
        return records
    }
}
