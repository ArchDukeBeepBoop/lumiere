import Foundation
import TestKit
import LumiereKit
import GRDB

/// What "Latest" ranks by.
///
/// The case that made this necessary is not hypothetical: Jellyfin stamps a Series
/// row with when its *folder* was scanned, so a library rescan makes every show look
/// newly added at once. On the real Anime library that left six shows whose newest
/// episode is from 2019 sitting at the head of the shelf, unchanged, because a
/// rescan is not something that happens again soon.
@MainActor
func registerContentDateTests(_ t: TestRunner) async {

    func makeRepository() throws -> (LibraryRepository, LibraryDatabase) {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!,
            serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        return (
            LibraryRepository(database: database, client: JellyfinClient(session: session, token: "t")),
            database
        )
    }

    func day(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(d) * 86_400) }

    func insert(
        _ database: LibraryDatabase, id: String, name: String, type: String,
        created: Date, seriesId: String? = nil
    ) throws {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": type]
        if let seriesId { json["SeriesId"] = seriesId }
        let data = try JSONSerialization.data(withJSONObject: json)
        var record = ItemRecord(
            from: try JellyfinClient.decoder.decode(JellyfinItem.self, from: data),
            serverId: "s1", syncedAt: Date()
        )
        record.libraryId = "lib"
        record.dateCreated = created
        record.contentDate = created
        try database.writer.write { db in try record.save(db) }
    }

    await t.suite("Latest ranks by content, not by folder") { t in

        await t.test("a rescanned series ranks by its newest episode, not its folder") {
            let (repository, database) = try makeRepository()
            // The rescan case: the folder was touched today, the episodes are old.
            try insert(database, id: "old", name: "Rescanned Show", type: "Series", created: day(10))
            try insert(database, id: "old-e", name: "Ep", type: "Episode",
                       created: day(1), seriesId: "old")
            // A show that genuinely got a new episode yesterday.
            try insert(database, id: "live", name: "Airing Show", type: "Series", created: day(2))
            try insert(database, id: "live-e", name: "Ep", type: "Episode",
                       created: day(9), seriesId: "live")

            try await repository.refreshContentDates(libraryId: "lib")

            let ranked = try await repository.entries(
                types: [.series], sort: .latestContent, descending: true, libraryId: "lib", limit: 10
            )
            t.expectEqual(ranked.map(\.item.name), ["Airing Show", "Rescanned Show"])

            // And the difference is real: by the row's own date the rescan wins,
            // which is exactly the shelf that stopped changing.
            let byRow = try await repository.entries(
                types: [.series], sort: .dateAdded, descending: true, libraryId: "lib", limit: 10
            )
            t.expectEqual(byRow.map(\.item.name), ["Rescanned Show", "Airing Show"])
        }

        await t.test("a series with no episodes keeps its own date") {
            // A show added before anything under it has synced must not sort as
            // null and vanish off the end of the shelf.
            let (repository, database) = try makeRepository()
            try insert(database, id: "bare", name: "Just Added", type: "Series", created: day(20))
            try insert(database, id: "film", name: "A Film", type: "Movie", created: day(5))

            try await repository.refreshContentDates(libraryId: "lib")

            let ranked = try await repository.entries(
                types: [.series, .movie], sort: .latestContent,
                descending: true, libraryId: "lib", limit: 10
            )
            t.expectEqual(ranked.map(\.item.name), ["Just Added", "A Film"])
        }

        await t.test("a film ranks by itself, having nothing underneath it") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "f1", name: "Newer", type: "Movie", created: day(9))
            try insert(database, id: "f2", name: "Older", type: "Movie", created: day(3))
            try await repository.refreshContentDates(libraryId: "lib")

            let ranked = try await repository.entries(
                types: [.movie], sort: .latestContent, descending: true, libraryId: "lib", limit: 10
            )
            t.expectEqual(ranked.map(\.item.name), ["Newer", "Older"])
        }

        await t.test("saving an item flattens the ranking, which is why sync refreshes") {
            // The regression this pins is not "the refresh is wrong" — it was right
            // — but "the refresh was not reached". Saving a row writes contentDate
            // as the row's own date, so every sync page undoes the ranking, and
            // three of the four ways out of a sync pass returned before putting it
            // back. The incremental path was one, and it runs on almost every
            // launch: the shelf was recomputed correctly and flattened seconds later.
            let (repository, database) = try makeRepository()
            try insert(database, id: "s", name: "Rescanned", type: "Series", created: day(10))
            try insert(database, id: "e", name: "Ep", type: "Episode",
                       created: day(1), seriesId: "s")

            try await repository.refreshContentDates(libraryId: "lib")
            let refined = try await database.writer.read { db in
                try Date.fetchOne(db, sql: "SELECT contentDate FROM item WHERE id = 's'")
            }
            t.expectEqual(refined, day(1))

            // What a sync page does to it.
            try insert(database, id: "s", name: "Rescanned", type: "Series", created: day(10))
            let clobbered = try await database.writer.read { db in
                try Date.fetchOne(db, sql: "SELECT contentDate FROM item WHERE id = 's'")
            }
            t.expectEqual(clobbered, day(10))

            // And that the refresh puts it back, which is why it has to run on
            // every exit path rather than only the one that reaches the bottom.
            try await repository.refreshContentDates(libraryId: "lib")
            let restored = try await database.writer.read { db in
                try Date.fetchOne(db, sql: "SELECT contentDate FROM item WHERE id = 's'")
            }
            t.expectEqual(restored, day(1))
        }

        t.test("the sort menu does not offer it") {
            // It is what a shelf named Latest means, not a column anybody picks.
            t.expect(
                !LibraryRepository.Sort.userSelectable.contains(.latestContent),
                "latestContent must stay out of the grid's sort menu"
            )
            t.expectEqual(LibraryRepository.Sort.userSelectable.count,
                          LibraryRepository.Sort.allCases.count - 1)
        }
    }
}
