import Foundation
import TestKit
import LumiereKit
import GRDB

/// The deletion sweep, and the empty-set case that made it catastrophic.
///
/// `syncLibrary` removes rows the server no longer returns. The predicate it uses,
/// `!liveIds.contains(Column("id"))`, is rendered by GRDB as `NOT 0` when the set is
/// empty — true of every row — so one response of `{"Items": []}` deleted an entire
/// library and every watch record keyed to it. Watch history is the one thing in
/// this cache that cannot be re-fetched, which is what makes this worth a test of
/// its own rather than a line in a sync test.
@MainActor
func registerSyncSweepTests(_ t: TestRunner) async {

    func seed(_ database: LibraryDatabase, ids: [String], libraryId: String) async throws {
        try await database.writer.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                        INSERT INTO item
                        (id, serverId, type, name, sortName, searchKey, isFolder, syncedAt, libraryId)
                        VALUES (?,?,?,?,?,?,?,?,?)
                        """,
                    arguments: [id, "s1", "Movie", id, id, id, false, Date(), libraryId]
                )
            }
        }
    }

    await t.suite("Sync deletion sweep") { t in

        await t.test("an empty live set matches every row, which is why it is guarded") {
            // Pins the GRDB behaviour the bug rested on. If a future version renders
            // an empty `contains` differently, this test says so rather than letting
            // the guard look like superstition.
            let database = try LibraryDatabase(inMemory: true)
            try await seed(database, ids: ["a", "b", "c"], libraryId: "lib")

            let empty: Set<String> = []
            let wouldSweep = try await database.writer.read { db in
                try ItemRecord
                    .filter(Column("libraryId") == "lib")
                    .filter(!empty.contains(Column("id")))
                    .fetchCount(db)
            }
            t.expectEqual(wouldSweep, 3)
        }

        await t.test("a non-empty live set spares exactly what it names") {
            let database = try LibraryDatabase(inMemory: true)
            try await seed(database, ids: ["a", "b", "c"], libraryId: "lib")

            let live: Set<String> = ["a"]
            let wouldSweep = try await database.writer.read { db in
                try ItemRecord
                    .filter(Column("libraryId") == "lib")
                    .filter(!live.contains(Column("id")))
                    .fetchCount(db)
            }
            t.expectEqual(wouldSweep, 2)
        }
    }
}
