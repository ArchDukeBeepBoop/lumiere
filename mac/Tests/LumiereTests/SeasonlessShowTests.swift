import Foundation
import TestKit
import LumiereKit
import GRDB

/// A show whose episodes sit straight under it, with no season at all.
@MainActor
func registerSeasonlessShowTests(_ t: TestRunner) async {
    t.suite("Unnumbered episodes") { t in
        t.test("episodes with one title and no number follow their filenames") {
            func loose(_ id: String, _ file: String) -> LibraryEntry {
                let data = try! JSONSerialization.data(withJSONObject: ["Id": id, "Name": "Bright Mornings", "Type": "Episode"])
                var item = ItemRecord(from: try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data),
                                      serverId: "s", syncedAt: Date())
                item.path = "/tv/Bright Mornings/" + file
                return LibraryEntry(item: item, userData: nil)
            }
            let ordered = [loose("c", "Bright Mornings 10.mkv"), loose("a", "Bright Mornings 2.mkv"), loose("b", "Bright Mornings 3.mkv")]
                .orderedAsEpisodes(byFilename: false)
            t.expectEqual(ordered.map(\.id), ["a", "b", "c"])
        }
    }

    t.suite("Loose files") { t in
        t.test("a special in the show's own folder was loose; one in Specials was not") {
            t.expect(LoosePlacement.wasLoose(season: 0, path: "/tv/Tylor/Tylor OVA 1.mkv"))
            t.expect(!LoosePlacement.wasLoose(season: 0, path: "/tv/Tylor/Specials/Tylor OVA 1.mkv"))
            t.expect(!LoosePlacement.wasLoose(season: 0, path: "/tv/Tylor/Season 00/x.mkv"))
            t.expect(!LoosePlacement.wasLoose(season: 1, path: "/tv/Elf/Elf - 01.mkv"))
        }
    }

    t.suite("Episode numbering") { t in
        t.test("a show with no seasons numbers its episodes plainly") {
            t.expectEqual(EpisodeCode.text(season: 2, episode: 5), "S2 E5")
            t.expectEqual(EpisodeCode.text(season: 2, episode: 5, compact: true), "S2E5")
            t.expectEqual(EpisodeCode.text(season: nil, episode: 5), "Episode 5")
            t.expect(EpisodeCode.text(season: 1, episode: nil) == nil)
        }
    }

    await t.suite("Shows with no seasons") { t in
        await t.test("their episodes come back from the cache, in order") {
            let database = try LibraryDatabase(inMemory: true)
            try await database.writer.write { db in
                let rows: [(String, String, String?, Int?)] = [
                    ("show", "Series", nil, nil), ("e2", "Episode", "show", 2), ("e1", "Episode", "show", 1),
                ]
                for (id, type, parent, number) in rows {
                    try db.execute(sql: """
                        INSERT INTO item (id, serverId, type, name, sortName, parentId, seriesId,
                                          indexNumber, isFolder, syncedAt)
                        VALUES (?, 's', ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [id, type, id, id, parent, parent, number, type == "Series", Date()])
                }
            }
            let session = JellyfinSession(
                serverURL: URL(string: "http://127.0.0.1:9")!, serverName: "x",
                serverId: "s", userId: "u", userName: "u", deviceId: "d")
            let repository = LibraryRepository(
                database: database, client: JellyfinClient(session: session, token: "t"))
            let episodes = try await repository.episodes(seriesId: "show", seasonId: nil)
            t.expectEqual(episodes.map(\.id), ["e1", "e2"])
        }
    }
}
