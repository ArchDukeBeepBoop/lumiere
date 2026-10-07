import Foundation
import TestKit
import LumiereKit
import GRDB

/// The change feed into the cache, and changes made while the server is away.
@MainActor
func registerChangeFeedTests(_ t: TestRunner) async {
    func offlineRepository() throws -> (LibraryRepository, LibraryDatabase) {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://127.0.0.1:9")!, serverName: "x",
            serverId: "s", userId: "u", userName: "u", deviceId: "d")
        return (LibraryRepository(database: database, client: JellyfinClient(session: session, token: "t")), database)
    }
    func addFilm(_ database: LibraryDatabase, _ id: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO item (id, serverId, type, name, sortName, libraryId, isFolder, syncedAt)
                VALUES (?, 's', 'Movie', ?, ?, 'films', 0, ?)
                """, arguments: [id, id, id, Date()])
            try db.execute(sql: "INSERT INTO itemDetail (itemId, json, fetchedAt) VALUES (?, '{}', ?)",
                           arguments: [id, Date()])
        }
    }

    await t.suite("Change feed") { t in
        t.test("the server's page decodes") {
            let page = try JSONDecoder().decode(ChangePage.self, from: Data(
                #"{"Next":42,"Reset":false,"Changed":["a"],"Removed":["b"],"More":true}"#.utf8))
            t.expectEqual(page.next, 42)
            t.expectEqual(page.changed, ["a"])
            t.expectEqual(page.removed, ["b"])
            t.expect(page.more)
        }

        await t.test("a removed title leaves the cache, saved page and all") {
            let (repository, database) = try offlineRepository()
            try await addFilm(database, "gone")
            try await addFilm(database, "kept")
            let result = try await repository.applyChanges(changed: [], removed: ["gone"], libraryIds: ["films"])
            t.expectEqual(result.removed, 1)
            let ids = try await database.writer.read { db in try String.fetchAll(db, sql: "SELECT id FROM item ORDER BY id") }
            t.expectEqual(ids, ["kept"])
            let pages = try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM itemDetail") }
            t.expectEqual(pages, 1)
        }

        await t.test("a favourite made with the server away stays, and waits to be sent") {
            let (repository, database) = try offlineRepository()
            try await addFilm(database, "film")
            let kept = await repository.setFavorite(itemId: "film", favorite: true)
            t.expect(kept)
            let favourite = try await database.writer.read { db in
                try Bool.fetchOne(db, sql: "SELECT isFavorite FROM userData WHERE itemId = 'film'")
            }
            t.expectEqual(favourite, true)
            let pending = await repository.pendingWrites()
            t.expectEqual(pending.map(\.itemId), ["film"])
            t.expectEqual(pending.first?.kind, .favorite)
        }
    }
}

@MainActor
func registerPreviewSyncTests(_ t: TestRunner) async {
    await t.suite("Drift") { t in
        await t.test("the cache's count is the library's rows only") {
            let database = try LibraryDatabase(inMemory: true)
            try await database.writer.write { db in
                for (id, library) in [("a", "films"), ("b", "films"), ("c", "shows")] {
                    try db.execute(sql: """
                        INSERT INTO item (id, serverId, type, name, sortName, libraryId, isFolder, syncedAt)
                        VALUES (?, 's', 'Movie', ?, ?, ?, 0, ?)
                        """, arguments: [id, id, id, library, Date()])
                }
            }
            let session = JellyfinSession(
                serverURL: URL(string: "http://127.0.0.1:9")!, serverName: "x",
                serverId: "s", userId: "u", userName: "u", deviceId: "d")
            let repository = LibraryRepository(database: database, client: JellyfinClient(session: session, token: "t"))
            t.expectEqual(await repository.cachedCount(libraryId: "films"), 2)
        }
    }
}
