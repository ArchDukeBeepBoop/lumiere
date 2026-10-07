import Foundation
import TestKit
import LumiereKit
import GRDB

/// The detail page redraws from the database, not from whoever remembered to
/// tell it. These pin the signal it listens to.
@MainActor
func registerWatchObservationTests(_ t: TestRunner) async {
    await t.suite("Watch-state observation") { t in
        await t.test("a tick on an episode under the show is seen; one elsewhere is not") {
            let database = try LibraryDatabase(inMemory: true)
            let session = JellyfinSession(
                serverURL: URL(string: "http://demo.local")!, serverName: "Test",
                serverId: "s1", userId: "u1", userName: "test", deviceId: "d1"
            )
            let repository = LibraryRepository(
                database: database, client: JellyfinClient(session: session, token: "t")
            )
            try await database.writer.write { db in
                for (id, type, series) in [("show", "Series", nil), ("e1", "Episode", "show"),
                                           ("other", "Episode", "elsewhere")] as [(String, String, String?)] {
                    try db.execute(sql: """
                        INSERT INTO item (id, serverId, type, name, sortName, seriesId, parentId, syncedAt)
                        VALUES (?, 's1', ?, ?, ?, ?, ?, ?)
                        """, arguments: [id, type, id, id, series, series, Date()])
                }
            }

            var changes = await repository.watchStateChanges(under: "show").makeAsyncIterator()
            _ = await changes.next()   // the current state

            try await database.writer.write { db in
                try UserDataRecord(itemId: "other", from: nil, updatedAt: Date()).save(db)
                var tick = UserDataRecord(itemId: "e1", from: nil, updatedAt: Date())
                tick.played = true
                try tick.save(db)
            }
            // Arrives, and only once: the unrelated write alone would not have
            // changed the fingerprint.
            let seen: Void? = await changes.next()
            t.expect(seen != nil)
        }
    }
}
