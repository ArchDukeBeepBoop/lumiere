import Foundation
import TestKit
import LumiereKit
import GRDB

// Shared by both halves of the library filter tests.
@MainActor

func makeRepository() throws -> (LibraryRepository, LibraryDatabase) {
    let database = try LibraryDatabase(inMemory: true)
    let session = JellyfinSession(
        serverURL: URL(string: "http://demo.local")!,
        serverName: "Test", serverId: "s1",
        userId: "u1", userName: "test", deviceId: "d1"
    )
    // No method under test issues a request, so the client is never reached.
    let client = JellyfinClient(session: session, token: "t")
    return (LibraryRepository(database: database, client: client), database)
}

func insert(
    _ database: LibraryDatabase,
    id: String,
    name: String,
    genres: [String] = [],
    year: Int? = nil,
    parentId: String = "lib",
    played: Bool = false,
    favourite: Bool = false
) throws {
    var json: [String: Any] = ["Id": id, "Name": name, "Type": "Movie"]
    if !genres.isEmpty { json["Genres"] = genres }
    if let year { json["ProductionYear"] = year }

    let data = try JSONSerialization.data(withJSONObject: json)
    let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
    var record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
    record.libraryId = parentId

    var userData = UserDataRecord(itemId: id, from: nil, updatedAt: Date())
    userData.played = played
    userData.isFavorite = favourite

    try database.writer.write { db in
        try record.insert(db)
        try userData.insert(db)
    }
}


/// The library filters read straight from the cache and never touch the network,
/// so they are testable end to end against an in-memory database — including the
/// part that matters most: that the count in the header agrees with the grid
/// beneath it.
@MainActor
func registerLibraryFilterTests(_ t: TestRunner) async {
    await t.suite("Library filters") { t in

        // Through `genreTallies` now: `genres()` was a second implementation of the
        // same question that applied none of the grid's filters, so it offered
        // genres whose grid came back empty. These assertions are unchanged — the
        // one query answers them the same way — and they now also pin that the
        // answer is restricted to the types a grid actually shows.
        await t.test("genres are collected from every item, deduplicated and sorted") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A", genres: ["Drama", "Thriller"])
            try insert(database, id: "2", name: "B", genres: ["Drama", "Comedy"])
            try insert(database, id: "3", name: "C")

            let genres = try await repository.genreTallies(types: LibraryRepository.topLevelTypes, libraryId: "lib").map(\.name).sorted()
            t.expectEqual(genres, ["Comedy", "Drama", "Thriller"])
        }

        await t.test("an item with no genres contributes nothing rather than an empty entry") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A")
            let genres = try await repository.genreTallies(types: LibraryRepository.topLevelTypes, libraryId: "lib").map(\.name).sorted()
            t.expect(genres.isEmpty, "expected no genres, got \(genres)")
        }

        await t.test("genres are scoped to the library asked for") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A", genres: ["Drama"], parentId: "movies")
            try insert(database, id: "2", name: "B", genres: ["Anime"], parentId: "tv")

            t.expectEqual(try await repository.genreTallies(types: LibraryRepository.topLevelTypes, libraryId: "movies").map(\.name).sorted(), ["Drama"])
            t.expectEqual(try await repository.genreTallies(types: LibraryRepository.topLevelTypes, libraryId: "tv").map(\.name).sorted(), ["Anime"])
        }

        await t.test("years come back newest first, without duplicates") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A", year: 1999)
            try insert(database, id: "2", name: "B", year: 2021)
            try insert(database, id: "3", name: "C", year: 1999)

            t.expectEqual(try await repository.years(libraryId: "lib"), [2021, 1999])
        }

        await t.test("the count agrees with the grid when a genre is filtered") {
            // The header saying "412 items" over a filtered grid of nine is worse
            // than no count at all, so the two share a filter set.
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A", genres: ["Drama"])
            try insert(database, id: "2", name: "B", genres: ["Drama"])
            try insert(database, id: "3", name: "C", genres: ["Comedy"])

            let rows = try await repository.entries(libraryId: "lib", limit: 100, genre: "Drama")
            let count = try await repository.count(libraryId: "lib", genre: "Drama")
            t.expectEqual(rows.count, 2)
            t.expectEqual(count, rows.count)
        }

        await t.test("the count agrees with the grid when unwatched is filtered") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A", played: true)
            try insert(database, id: "2", name: "B", played: false)
            try insert(database, id: "3", name: "C", played: false)

            let rows = try await repository.entries(
                libraryId: "lib", limit: 100, unwatchedOnly: true
            )
            let count = try await repository.count(libraryId: "lib", unwatchedOnly: true)
            t.expectEqual(rows.count, 2)
            t.expectEqual(count, rows.count)
        }

        await t.test("genre and unwatched compose rather than override each other") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A", genres: ["Drama"], played: true)
            try insert(database, id: "2", name: "B", genres: ["Drama"], played: false)
            try insert(database, id: "3", name: "C", genres: ["Comedy"], played: false)

            let rows = try await repository.entries(
                libraryId: "lib", limit: 100, genre: "Drama", unwatchedOnly: true
            )
            t.expectEqual(rows.count, 1)
            t.expectEqual(rows.first?.item.id, "2")
        }

        await t.test("favourites return only starred items, sorted by title") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Zulu", favourite: true)
            try insert(database, id: "2", name: "Alpha", favourite: true)
            try insert(database, id: "3", name: "Beta", favourite: false)

            let favourites = try await repository.favouriteEntries()
            t.expectEqual(favourites.map(\.item.id), ["2", "1"])
        }

        await t.test("hiding an item keeps it out of the shelves but in the library") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Keep")
            try insert(database, id: "2", name: "Hide")

            try await repository.hideFromShelves(itemId: "2")
            t.expectEqual(try await repository.hiddenShelfIds(), ["2"])

            // Still a library item — hiding concerns two shelves, not deletion.
            let all = try await repository.entries(libraryId: "lib", limit: 100)
            t.expectEqual(all.count, 2)
        }

        await t.test("unhiding restores it, so the list is not a one-way door") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Hide")
            try await repository.hideFromShelves(itemId: "1")
            try await repository.unhideFromShelves(itemId: "1")
            t.expect(try await repository.hiddenShelfIds().isEmpty)
        }

        await t.test("the hidden list names its items, which the Settings list shows") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Hidden Thing")
            try await repository.hideFromShelves(itemId: "1")
            t.expectEqual(try await repository.hiddenShelfEntries().map(\.item.name), ["Hidden Thing"])
        }

        await t.test("hiding the same item twice is not an error") {
            // The menu can be used twice before the shelf reloads.
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A")
            try await repository.hideFromShelves(itemId: "1")
            try await repository.hideFromShelves(itemId: "1")
            t.expectEqual(try await repository.hiddenShelfIds().count, 1)
        }

        await t.test("clearing the hidden list empties it, leaving the library alone") {
            // Exactly what the confirmation dialog promises: the history goes, the
            // items stay.
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A")
            try insert(database, id: "2", name: "B")
            try await repository.hideFromShelves(itemId: "1")
            try await repository.hideFromShelves(itemId: "2")

            try await repository.clearHiddenShelfItems()

            t.expect(try await repository.hiddenShelfIds().isEmpty)
            t.expectEqual(try await repository.entries(libraryId: "lib", limit: 100).count, 2)
        }

        await t.test("clearing an already-empty hidden list is not an error") {
            let (repository, _) = try makeRepository()
            try await repository.clearHiddenShelfItems()
            t.expect(try await repository.hiddenShelfIds().isEmpty)
        }

        t.test("seasons order by number, not by title") {
            // Alphabetically "Season 10" precedes "Season 2", so every show with ten
            // or more seasons was listed wrongly.
            func season(_ number: Int?, _ name: String) -> LibraryEntry {
                var record = ItemRecord(
                    from: try! JellyfinClient.decoder.decode(
                        JellyfinItem.self,
                        from: try! JSONSerialization.data(withJSONObject: [
                            "Id": name, "Name": name, "Type": "Season",
                        ] as [String: Any])
                    ),
                    serverId: "s1", syncedAt: Date()
                )
                record.indexNumber = number
                return LibraryEntry(item: record, userData: nil)
            }

            let ordered = [
                season(10, "Season 10"), season(2, "Season 2"),
                season(0, "Specials"), season(1, "Season 1"),
            ].orderedAsSeasons

            // Specials last: it supplements the seasons rather than preceding them.
            t.expectEqual(ordered.map(\.item.indexNumber), [1, 2, 10, 0])
        }

    }
}
