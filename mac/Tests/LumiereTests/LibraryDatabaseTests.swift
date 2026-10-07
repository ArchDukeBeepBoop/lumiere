import Foundation
import TestKit
import LumiereKit
import GRDB

@MainActor
func registerLibraryDatabaseTests(_ t: TestRunner) async {

    t.suite("Sort keys") { t in

        t.test("leading articles are ignored so The Batman files under B") {
            t.expectEqual(ItemRecord.normalizedTitle("The Batman"), "batman")
            t.expectEqual(ItemRecord.normalizedTitle("A Quiet Place"), "quiet place")
            t.expectEqual(ItemRecord.normalizedTitle("An Education"), "education")
        }

        t.test("an article inside the title is left alone") {
            t.expectEqual(ItemRecord.normalizedTitle("Theatre of Blood"), "theatre of blood")
            t.expectEqual(ItemRecord.normalizedTitle("Anatomy of a Fall"), "anatomy of a fall")
        }

        t.test("sorting is case-insensitive") {
            t.expectEqual(ItemRecord.normalizedTitle("DUNE"), "dune")
        }

        t.test("episodes sort by season then number, not by title") {
            let e1 = ItemRecord.sortKey(for: makeEpisode(season: 2, episode: 4))
            let e2 = ItemRecord.sortKey(for: makeEpisode(season: 2, episode: 10))
            let e3 = ItemRecord.sortKey(for: makeEpisode(season: 10, episode: 1))
            t.expect(e1 < e2, "E4 should sort before E10, got \(e1) vs \(e2)")
            t.expect(e2 < e3, "S2 should sort before S10, got \(e2) vs \(e3)")
        }

        t.test("an episode with no numbering still produces a stable key") {
            let key = ItemRecord.sortKey(for: makeEpisode(season: nil, episode: nil))
            t.expectEqual(key, "00000000")
        }
    }

    await t.suite("Library database") { t in

        t.test("migrations apply to a fresh in-memory database") {
            let db = try LibraryDatabase(inMemory: true)
            let tables = try db.writer.read { db in
                try String.fetchAll(
                    db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                )
            }
            for expected in ["item", "userData", "library", "syncState"] {
                t.expect(tables.contains(expected), "missing table \(expected)")
            }
        }

        t.test("an item round-trips through the cache") {
            let db = try LibraryDatabase(inMemory: true)
            let record = ItemRecord(
                from: makeMovie(id: "m1", name: "The Batman", year: 2022),
                serverId: "s1",
                syncedAt: Date()
            )
            try db.writer.write { try record.insert($0) }

            let loaded = try db.writer.read { try ItemRecord.fetchOne($0, key: "m1") }
            t.expectEqual(loaded?.name, "The Batman")
            t.expectEqual(loaded?.sortName, "batman")
            t.expectEqual(loaded?.productionYear, 2022)
        }

        t.test("genres round-trip as a list") {
            let db = try LibraryDatabase(inMemory: true)
            var item = makeMovie(id: "m2", name: "Dune", year: 2021)
            item = withGenres(item, ["Science Fiction", "Adventure"])
            let record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
            try db.writer.write { try record.insert($0) }

            let loaded = try db.writer.read { try ItemRecord.fetchOne($0, key: "m2") }
            t.expectEqual(loaded?.genreList, ["Science Fiction", "Adventure"])
        }

        t.test("an item with no genres reads back as an empty list, not [\"\"]") {
            let db = try LibraryDatabase(inMemory: true)
            let record = ItemRecord(
                from: makeMovie(id: "m3", name: "X", year: nil), serverId: "s1", syncedAt: Date()
            )
            try db.writer.write { try record.insert($0) }
            let loaded = try db.writer.read { try ItemRecord.fetchOne($0, key: "m3") }
            t.expectEqual(loaded?.genreList, [])
        }

        await t.test("reset clears every table") {
            let db = try LibraryDatabase(inMemory: true)
            let record = ItemRecord(
                from: makeMovie(id: "m4", name: "X", year: nil), serverId: "s1", syncedAt: Date()
            )
            try await db.writer.write { try record.insert($0) }

            try await db.reset()

            let count = try await db.writer.read { try ItemRecord.fetchCount($0) }
            t.expectEqual(count, 0)
        }

        t.test("a windowed query returns only the window, not the library") {
            let db = try LibraryDatabase(inMemory: true)
            try db.writer.write { conn in
                for index in 0..<500 {
                    try ItemRecord(
                        from: makeMovie(id: "m\(index)", name: "Film \(index)", year: 2000),
                        serverId: "s1",
                        syncedAt: Date()
                    ).insert(conn)
                }
            }

            // The point of the cache: a 500-item library yields 60 rows for a grid.
            let page = try db.writer.read { conn in
                try ItemRecord.order(Column("sortName")).limit(60, offset: 0).fetchAll(conn)
            }
            t.expectEqual(page.count, 60)

            let total = try db.writer.read { try ItemRecord.fetchCount($0) }
            t.expectEqual(total, 500)
        }
    }

    t.suite("Watch progress") { t in

        t.test("progress is the watched fraction of the runtime") {
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 9_000_000_000, played: false)
            t.expectEqual(entry.progress, 0.25)
        }

        t.test("a finished item reports no progress bar") {
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 9_000_000_000, played: true)
            t.expectNil(entry.progress)
        }

        t.test("an untouched item reports no progress bar") {
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 0, played: false)
            t.expectNil(entry.progress)
        }

        t.test("progress cannot exceed 1 even if the server overshoots") {
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 40_000_000_000, played: false)
            t.expectEqual(entry.progress, 1.0)
        }

        t.test("remaining time reads in minutes under an hour") {
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 18_000_000_000, played: false)
            t.expectEqual(entry.remainingText, "30m left")
        }

        t.test("remaining time reads in hours and minutes over an hour") {
            // 2h 44m runtime, 12m watched -> 2h 32m left.
            let entry = makeEntry(runtimeTicks: 98_400_000_000, positionTicks: 7_200_000_000, played: false)
            t.expectEqual(entry.remainingText, "2h 32m left")
        }

        t.test("an item with unknown runtime reports no progress") {
            let entry = makeEntry(runtimeTicks: nil, positionTicks: 9_000_000_000, played: false)
            t.expectNil(entry.progress)
            t.expectNil(entry.remainingText)
        }
    }

    t.suite("Where playback starts") { t in

        t.test("a part-watched item resumes where it was left") {
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 9_000_000_000, played: false)
            t.expectEqual(entry.resumeStart, 900)
        }

        t.test("a watched item starts from the beginning, not from its last position") {
            // The reported bug: finishing an episode leaves the final position in
            // the cache, so going back to it resumed at the end — a black frame with
            // -0:00 on the scrubber, which reads as the player having failed.
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 35_000_000_000, played: true)
            t.expectEqual(entry.resumeStart, 0)
        }

        t.test("a position inside the last ten seconds starts from the beginning") {
            // Abandoned during the credits is finished, whatever the played flag
            // says: resuming there gives you a fade to black.
            let entry = makeEntry(runtimeTicks: 36_000_000_000, positionTicks: 35_960_000_000, played: false)
            t.expectEqual(entry.resumeStart, 0)
        }

        t.test("an unknown runtime still honours the stored position") {
            let entry = makeEntry(runtimeTicks: nil, positionTicks: 9_000_000_000, played: false)
            t.expectEqual(entry.resumeStart, 900)
        }
    }
}

// MARK: - Builders

@MainActor
private func decodeItem(_ json: [String: Any]) -> JellyfinItem {
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
}

@MainActor
private func makeMovie(id: String, name: String, year: Int?) -> JellyfinItem {
    var json: [String: Any] = ["Id": id, "Name": name, "Type": "Movie"]
    if let year { json["ProductionYear"] = year }
    return decodeItem(json)
}

@MainActor
private func withGenres(_ item: JellyfinItem, _ genres: [String]) -> JellyfinItem {
    decodeItem([
        "Id": item.id, "Name": item.name, "Type": item.type.rawValue, "Genres": genres,
    ])
}

@MainActor
private func makeEpisode(season: Int?, episode: Int?) -> JellyfinItem {
    var json: [String: Any] = ["Id": "e", "Name": "Episode", "Type": "Episode"]
    if let season { json["ParentIndexNumber"] = season }
    if let episode { json["IndexNumber"] = episode }
    return decodeItem(json)
}

@MainActor
private func makeEntry(runtimeTicks: Int64?, positionTicks: Int64, played: Bool) -> LibraryEntry {
    var json: [String: Any] = ["Id": "x", "Name": "X", "Type": "Movie"]
    if let runtimeTicks { json["RunTimeTicks"] = runtimeTicks }
    let item = ItemRecord(from: decodeItem(json), serverId: "s1", syncedAt: Date())

    let userDataJSON: [String: Any] = [
        "PlaybackPositionTicks": positionTicks, "Played": played,
    ]
    let data = try! JSONSerialization.data(withJSONObject: userDataJSON)
    let userItemData = try! JellyfinClient.decoder.decode(UserItemData.self, from: data)

    return LibraryEntry(
        item: item,
        userData: UserDataRecord(itemId: "x", from: userItemData, updatedAt: Date())
    )
}

