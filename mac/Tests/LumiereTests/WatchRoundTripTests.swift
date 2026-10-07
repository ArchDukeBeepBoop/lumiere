import Foundation
import TestKit
import LumiereKit
import GRDB

/// A season ticked and unticked, end to end through the repository.
///
/// Against a server that refuses — a closed port — because the refusal path
/// is the one that can quietly wreck a season: the rollback once restored the
/// season's own flag, which is rarely set, and so unticked every episode of a
/// season that had been fully watched.
@MainActor
func registerWatchRoundTripTests(_ t: TestRunner) async {
    await t.suite("Watch state round trip") { t in

        await t.test("a refused tick on a finished season leaves it finished") {
            let (repository, database) = try seasonFixture(watched: true)
            let ok = await repository.setPlayed(itemId: "s1", played: false)
            t.expect(!ok)
            let (played, count) = try await state(database)
            t.expectEqual(played, 2)
            t.expectEqual(count, 0)
        }

        await t.test("a refused Mark Unwatched on a season puts every episode back") {
            let (repository, database) = try seasonFixture(watched: true)
            let ok = await repository.clearWatchState(itemId: "s1")
            t.expect(!ok)
            let (played, count) = try await state(database)
            t.expectEqual(played, 2)
            t.expectEqual(count, 0)
        }

        await t.test("undo puts back each episode as it was, position included") {
            let (repository, database) = try seasonFixture(watched: false)
            try await database.writer.write { db in
                var partway = try UserDataRecord.fetchOne(db, key: "e2")!
                partway.playbackPositionTicks = 6_000_000_000
                try partway.save(db)
            }
            let snapshot = try await repository.watchSnapshot(of: "s1")
            t.expectEqual(snapshot.states.count, 2)
            // What marking the season did, before anyone regretted it.
            try await database.writer.write { db in
                for id in ["e1", "e2"] {
                    var data = try UserDataRecord.fetchOne(db, key: id)!
                    data.played = true
                    data.playbackPositionTicks = 0
                    try data.save(db)
                }
            }
            _ = await repository.restore(snapshot)
            let (played, count) = try await state(database)
            t.expectEqual(played, 0)
            t.expectEqual(count, 2)
            let position = try await database.writer.read { db in
                try UserDataRecord.fetchOne(db, key: "e2")?.playbackPositionTicks
            }
            t.expectEqual(position, 6_000_000_000)
        }

        await t.test("a tick with the server away stays, and waits to be sent") {
            let (repository, database) = try seasonFixture(watched: false, away: true)
            let ok = await repository.setPlayed(itemId: "s1", played: true)
            t.expect(ok)
            let (played, count) = try await state(database)
            t.expectEqual(played, 2)
            t.expectEqual(count, 0)
            t.expectEqual(await repository.pendingWrites().map(\.itemId), ["s1"])
        }

        await t.test("a refused tick on an unwatched season leaves it unwatched") {
            let (repository, database) = try seasonFixture(watched: false)
            _ = await repository.setPlayed(itemId: "s1", played: true)
            let (played, count) = try await state(database)
            t.expectEqual(played, 0)
            t.expectEqual(count, 2)
        }
    }
}

/// A season of two episodes, both watched or neither, with the count to match —
/// and the season's own flag left unset, as a real library leaves it.
/// One server for the whole run; it only ever says no.
private let refusing = RefusingServer()

private func seasonFixture(watched: Bool, away: Bool = false) throws -> (LibraryRepository, LibraryDatabase) {
    let database = try LibraryDatabase(inMemory: true)
    let session = JellyfinSession(
        serverURL: away ? URL(string: "http://127.0.0.1:9")! : refusing.url, serverName: "Refuses",
        serverId: "s", userId: "u", userName: "test", deviceId: "d"
    )
    try database.writer.write { db in
        let rows: [(String, String, String?, String?)] = [
            ("show", "Series", nil, nil), ("s1", "Season", "show", nil),
            ("e1", "Episode", "s1", "s1"), ("e2", "Episode", "s1", "s1"),
        ]
        for (id, type, parent, season) in rows {
            try db.execute(sql: """
                INSERT INTO item (id, serverId, type, name, sortName, parentId, seriesId,
                                  seasonId, isFolder, syncedAt)
                VALUES (?, 's', ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, type, id, id, parent, id == "show" ? nil : "show",
                                 season, type != "Episode", Date()])
        }
        for id in ["e1", "e2"] {
            var data = UserDataRecord(itemId: id, from: nil, updatedAt: Date())
            data.played = watched
            try data.save(db)
        }
        var season = UserDataRecord(itemId: "s1", from: nil, updatedAt: Date())
        season.unplayedItemCount = watched ? 0 : 2
        try season.save(db)
    }
    return (LibraryRepository(database: database, client: JellyfinClient(session: session, token: "t")),
            database)
}

/// How many of the two episodes are watched, and the season's count.
private func state(_ database: LibraryDatabase) async throws -> (Int, Int?) {
    try await database.writer.read { db in
        let played = try Int.fetchOne(db, sql: """
            SELECT count(*) FROM userData WHERE itemId IN ('e1','e2') AND played = 1
            """) ?? 0
        let count = try UserDataRecord.fetchOne(db, key: "s1")?.unplayedItemCount
        return (played, count)
    }
}
