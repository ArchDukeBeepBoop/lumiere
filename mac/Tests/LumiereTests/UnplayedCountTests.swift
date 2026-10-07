import Foundation
import TestKit
import LumiereKit
import GRDB

/// The number a season's unwatched corner is drawn from.
@MainActor
func registerUnplayedCountTests(_ t: TestRunner) async {

    t.suite("Unplayed counts") { t in

        t.test("a season is a count, a film is its own flag") {
            t.expect(UnplayedCount.isContainer(.season))
            t.expect(UnplayedCount.isContainer(.series))
            t.expect(!UnplayedCount.isContainer(.movie))
            t.expect(!UnplayedCount.isContainer(.episode))
        }

        t.test("extras do not keep a season unfinished") {
            t.expect(UnplayedCount.counts(type: .episode, extraType: nil))
            t.expect(!UnplayedCount.counts(type: .episode, extraType: "Clip"))
            t.expect(!UnplayedCount.counts(type: .season, extraType: nil))
        }
    }

    await t.suite("Unplayed counts in the cache") { t in

        await t.test("marking a season watched empties its count, and the show's") {
            let database = try LibraryDatabase(inMemory: true)
            try await database.writer.write { db in
                try put(db, id: "show", type: "Series")
                try put(db, id: "s1", type: "Season", parentId: "show", seriesId: "show")
                try put(db, id: "s2", type: "Season", parentId: "show", seriesId: "show")
                for id in ["e1", "e2"] {
                    try put(db, id: id, type: "Episode", parentId: "s1", seriesId: "show", seasonId: "s1")
                }
                try put(db, id: "e3", type: "Episode", parentId: "s2", seriesId: "show", seasonId: "s2")
                // An extra under the season, left unwatched on purpose.
                try put(db, id: "ncop", type: "Episode", parentId: "s1", seriesId: "show",
                        seasonId: "s1", extraType: "Clip")
                for id in ["e1", "e2", "e3"] {
                    try UserDataRecord(itemId: id, from: nil, updatedAt: Date()).save(db)
                }

                // Season one is watched.
                for id in ["e1", "e2"] {
                    var data = try UserDataRecord.fetchOne(db, key: id)!
                    data.played = true
                    try data.save(db)
                }
                try LibraryRepository.recountUnplayed("s1", in: db)
                try LibraryRepository.recountUnplayed("show", in: db)
            }

            let counts = try await database.writer.read { db -> [String: Int?] in
                var out: [String: Int?] = [:]
                for id in ["s1", "s2", "show"] {
                    out[id] = try UserDataRecord.fetchOne(db, key: id)?.unplayedItemCount
                }
                return out
            }
            t.expectEqual(counts["s1"] ?? nil, 0, "the watched season should read as finished")
            t.expectEqual(counts["show"] ?? nil, 1, "one episode of season two is still unwatched")
        }

        await t.test("a season's ancestors are the show above it") {
            let database = try LibraryDatabase(inMemory: true)
            let found = try await database.writer.write { db -> [String] in
                try put(db, id: "show", type: "Series")
                try put(db, id: "s1", type: "Season", parentId: "show", seriesId: "show")
                try put(db, id: "e1", type: "Episode", parentId: "s1", seriesId: "show", seasonId: "s1")
                return try LibraryRepository.ancestors(of: "e1", in: db)
            }
            t.expectEqual(found, ["s1", "show"])
        }
    }
}

/// Not main-actor isolated: it runs inside GRDB's write block, which is not.
private func put(
    _ db: Database, id: String, type: String, parentId: String? = nil,
    seriesId: String? = nil, seasonId: String? = nil, extraType: String? = nil
) throws {
    var json: [String: Any] = ["Id": id, "Name": id, "Type": type]
    if let parentId { json["ParentId"] = parentId }
    if let seriesId { json["SeriesId"] = seriesId }
    if let seasonId { json["SeasonId"] = seasonId }
    if let extraType { json["ExtraType"] = extraType }
    let data = try JSONSerialization.data(withJSONObject: json)
    let item = try JSONDecoder().decode(JellyfinItem.self, from: data)
    try ItemRecord(from: item, serverId: "s1", syncedAt: Date()).save(db)
}
