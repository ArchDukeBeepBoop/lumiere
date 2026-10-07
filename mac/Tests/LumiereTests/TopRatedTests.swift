import Foundation
import TestKit
import LumiereKit
import GRDB

/// The settling period on the Top 10 rows.
///
/// Measured against the real library, the unfiltered rating sort put *Aeronautica
/// Imperialis* at 10.0 and *Lessons Learned* at 9.4 above Breaking Bad — both
/// released within six months, both a few dozen votes deep. Jellyfin's payload has
/// no vote count, so release age is the only confidence signal there is, and this
/// pins the one rule that turns the ranking back into a ranking.
@MainActor
func registerTopRatedTests(_ t: TestRunner) async {

    func makeRepository() throws -> (LibraryRepository, LibraryDatabase) {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!,
            serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        let client = JellyfinClient(session: session, token: "t")
        return (LibraryRepository(database: database, client: client), database)
    }

    func insert(
        _ database: LibraryDatabase,
        id: String, name: String, rating: Double?, premiere: Date?
    ) throws {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": "Movie"]
        if let rating { json["CommunityRating"] = rating }
        if let premiere {
            json["PremiereDate"] = ISO8601DateFormatter().string(from: premiere)
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        var record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
        record.libraryId = "lib"
        try database.writer.write { db in
            try record.insert(db)
            try UserDataRecord(itemId: id, from: nil, updatedAt: Date()).insert(db)
        }
    }

    // Whole seconds. The insert round-trips the date through an ISO8601 string, which
    // drops the fractional part, so a `Date()` cutoff would come back a few hundred
    // microseconds earlier and the boundary case below would pass for the wrong reason.
    let now = Date(timeIntervalSince1970: (Date().timeIntervalSince1970).rounded(.down))
    let cutoff = now.addingTimeInterval(-180 * 24 * 60 * 60)

    await t.suite("Top rated") { t in

        await t.test("a fresh release outranking a classic is excluded") {
            let (repository, database) = try makeRepository()
            try insert(
                database, id: "new", name: "Last Month's Darling",
                rating: 10.0, premiere: now.addingTimeInterval(-30 * 24 * 60 * 60)
            )
            try insert(
                database, id: "old", name: "The Classic",
                rating: 8.7, premiere: now.addingTimeInterval(-8000 * 24 * 60 * 60)
            )

            let unfiltered = try await repository.entries(
                sort: .rating, descending: true, limit: 10
            )
            t.expect(unfiltered.first?.item.name == "Last Month's Darling",
                     "without the filter the fresh release leads")

            let settled = try await repository.entries(
                sort: .rating, descending: true, limit: 10, releasedBefore: cutoff
            )
            t.expect(settled.map(\.item.name) == ["The Classic"],
                     "with it, only the settled rating survives")
        }

        await t.test("a title with no release date is kept") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "undated", name: "Undated", rating: 9.0, premiere: nil)

            let settled = try await repository.entries(
                sort: .rating, descending: true, limit: 10, releasedBefore: cutoff
            )
            t.expect(settled.map(\.item.name) == ["Undated"],
                     "an absent date is not evidence of a fresh release")
        }

        await t.test("the boundary is exclusive, so the cutoff day itself is out") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "edge", name: "On The Day", rating: 9.0, premiere: cutoff)

            let settled = try await repository.entries(
                sort: .rating, descending: true, limit: 10, releasedBefore: cutoff
            )
            t.expect(settled.isEmpty, "released before means strictly before")
        }
    }
}

/// Decoding the server's task list.
///
/// Matched on `Key` rather than `Name` because the name is localised — a server in
/// French would have silently had no trickplay task at all.
@MainActor
func registerScheduledTaskTests(_ t: TestRunner) async {
    t.suite("Scheduled tasks") { t in

        t.test("the trickplay task is found by key, not by name") {
            let json = """
            [
              {"Id":"a1","Name":"Analyse d'images trickplay",
               "Key":"RefreshTrickplayImages","State":"Idle"},
              {"Id":"b2","Name":"Scan Media Library","Key":"RefreshLibrary","State":"Idle"}
            ]
            """.data(using: .utf8)!
            let tasks = try JSONDecoder().decode([ScheduledTask].self, from: json)
            let trickplay = tasks.first { $0.key == JellyfinClient.trickplayTaskKey }
            t.expectEqual(trickplay?.id, "a1")
        }

        t.test("a running task reports itself as running") {
            let json = """
            [{"Id":"a1","Name":"T","Key":"RefreshTrickplayImages",
              "State":"Running","CurrentProgressPercentage":42.5}]
            """.data(using: .utf8)!
            let task = try JSONDecoder().decode([ScheduledTask].self, from: json)[0]
            t.expect(task.isRunning)
            t.expectEqual(task.currentProgressPercentage, 42.5)
        }

        t.test("a server with no trickplay task decodes rather than throwing") {
            // Jellyfin before 10.9. The card has to tell that apart from "present
            // and never run", so the absence must be a nil and not an error.
            let json = """
            [{"Id":"b2","Name":"Scan Media Library","Key":"RefreshLibrary","State":"Idle"}]
            """.data(using: .utf8)!
            let tasks = try JSONDecoder().decode([ScheduledTask].self, from: json)
            t.expectNil(tasks.first { $0.key == JellyfinClient.trickplayTaskKey })
        }
    }
}
