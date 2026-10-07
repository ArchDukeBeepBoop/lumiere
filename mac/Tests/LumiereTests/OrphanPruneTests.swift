import Foundation
import TestKit
import LumiereKit
import GRDB

/// The rows no library sweep can reach, and the ones that only look like them.
///
/// This is the cache's one leak: `syncLibrary`'s deletion sweep matches on
/// `libraryId`, so a row cached without one survives every sync forever. On a real
/// 44,000-item library that was 3,234 rows, 1,181 of them pointing at files that no
/// longer existed. The prune has to remove exactly those and nothing else — the
/// three keep-cases below are each something that would be unrecoverable if it went.
@MainActor
func registerOrphanPruneTests(_ t: TestRunner) async {

    func makeRepository() throws -> (LibraryRepository, LibraryDatabase) {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!,
            serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        // The prune is pure SQL; the client is never reached.
        let client = JellyfinClient(session: session, token: "t")
        return (LibraryRepository(database: database, client: client), database)
    }

    /// A cached row, described by the three things the prune actually looks at.
    func insert(
        _ database: LibraryDatabase,
        id: String,
        type: String = "Audio",
        libraryId: String? = nil,
        extraType: String? = nil,
        cachedDaysAgo: Double = 7,
        played: Bool = false,
        favourite: Bool = false,
        resumeTicks: Int64 = 0,
        withUserData: Bool = true
    ) throws {
        let json: [String: Any] = ["Id": id, "Name": id, "Type": type]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        var record = ItemRecord(
            from: item, serverId: "s1",
            syncedAt: Date().addingTimeInterval(-cachedDaysAgo * 86_400)
        )
        record.libraryId = libraryId
        record.extraType = extraType

        try database.writer.write { db in
            try record.insert(db)
            if withUserData {
                var userData = UserDataRecord(itemId: id, from: nil, updatedAt: Date())
                userData.played = played
                userData.isFavorite = favourite
                userData.playbackPositionTicks = resumeTicks
                try userData.insert(db)
            }
        }
    }

    // These read and write through non-async helpers deliberately: GRDB offers both
    // a synchronous and an async `read`/`write`, and inside an async test body the
    // compiler picks the async one, which then needs an `await` the closure cannot
    // carry. A plain function keeps the sync overload in view.
    func ids(_ database: LibraryDatabase) throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM item ORDER BY id")
        }
    }

    func userDataCount(_ database: LibraryDatabase) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM userData") ?? 0
        }
    }

    func rank(_ database: LibraryDatabase, itemId: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO collectionRank (collectionId, itemId, rank, updatedAt) "
                   + "VALUES (?, ?, ?, ?)",
                arguments: ["c1", itemId, 0, Date()]
            )
        }
    }

    let cutoff = Date().addingTimeInterval(-3600)

    await t.suite("Unreachable row prune") { t in

        await t.test("a row with no library and no history goes") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "orphan")
            let removed = await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expectEqual(removed, 1)
            t.expect(try ids(database).isEmpty, "expected the orphan to be gone")
        }

        await t.test("a row that belongs to a library is never touched") {
            // The sweep owns these. Deleting one here would delete real library
            // rows on a machine that had merely not synced recently.
            let (repository, database) = try makeRepository()
            try insert(database, id: "member", type: "Movie", libraryId: "lib")
            await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expectEqual(try ids(database), ["member"])
        }

        await t.test("an extra is kept — something reads it") {
            // `extras(itemId:)` caches these deliberately so a detail page seen
            // once still lists its trailers offline. They have no libraryId by
            // construction, which is exactly what makes them look prunable.
            let (repository, database) = try makeRepository()
            try insert(database, id: "trailer", type: "Video", extraType: "Trailer")
            await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expectEqual(try ids(database), ["trailer"])
        }

        await t.test("watch history is never traded for tidiness") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "played", played: true)
            try insert(database, id: "resuming", resumeTicks: 5_000_000)
            try insert(database, id: "starred", favourite: true)
            try insert(database, id: "nothing")

            let removed = await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expectEqual(removed, 1)
            t.expectEqual(try ids(database), ["played", "resuming", "starred"])
        }

        await t.test("a zeroed userData row does not count as history") {
            // Every page of music writes one of these alongside the item, so
            // treating a bare row as history would keep the entire leak.
            let (repository, database) = try makeRepository()
            try insert(database, id: "orphan", withUserData: true)
            await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expect(try ids(database).isEmpty, "expected the orphan to be gone")
            t.expectEqual(try userDataCount(database), 0)
        }

        await t.test("a row cached moments ago is left alone") {
            // The music browser may be looking at it right now: these rows are
            // written as a page arrives, and the browser reads them straight back.
            let (repository, database) = try makeRepository()
            try insert(database, id: "fresh", cachedDaysAgo: 0)
            await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expectEqual(try ids(database), ["fresh"])
        }

        await t.test("a row a collection has ordered is kept") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "ranked", type: "Movie")
            try rank(database, itemId: "ranked")
            await repository.pruneUnreachableRows(cachedBefore: cutoff)
            t.expectEqual(try ids(database), ["ranked"])
        }
    }

    t.suite("Watch state of an entry") { t in

        func entry(type: String, played: Bool?, unplayed: Int? = nil) throws -> LibraryEntry {
            let data = try JSONSerialization.data(
                withJSONObject: ["Id": "1", "Name": "x", "Type": type]
            )
            let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
            let record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
            guard let played else { return LibraryEntry(item: record, userData: nil) }
            var userData = UserDataRecord(itemId: "1", from: nil, updatedAt: Date())
            userData.played = played
            userData.unplayedItemCount = unplayed
            return LibraryEntry(item: record, userData: userData)
        }

        t.test("a film is its own played flag") {
            t.expect(try entry(type: "Movie", played: true).isPlayed, "expected played")
            t.expect(!(try entry(type: "Movie", played: false).isPlayed), "expected unplayed")
            t.expect(!(try entry(type: "Movie", played: nil).isPlayed), "no data is unplayed")
        }

        t.test("a show is watched only when nothing under it is left") {
            // Same rule as the unwatched corner on a poster, so a tile cannot carry
            // an unwatched marker over a "Mark as Unwatched" command.
            t.expect(try entry(type: "Series", played: false, unplayed: 0).isPlayed,
                     "expected a series with nothing unplayed to count as watched")
            t.expect(!(try entry(type: "Series", played: true, unplayed: 3).isPlayed),
                     "expected a series with three unplayed episodes to count as unwatched")
        }

        t.test("the command is offered on content and withheld from the rest") {
            t.expect(try entry(type: "Video", played: nil).supportsWatchState,
                     "a loose video file can be marked watched")
            t.expect(try entry(type: "Folder", played: nil).supportsWatchState,
                     "a folder is the unit in a folder-browsed library")
            t.expect(!(try entry(type: "Person", played: nil).supportsWatchState),
                     "a person has no watch state")
            t.expect(!(try entry(type: "CollectionFolder", played: nil).supportsWatchState),
                     "a library is not content")
        }
    }
}
