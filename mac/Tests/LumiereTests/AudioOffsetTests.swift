import Foundation
import TestKit
import LumiereKit

/// Per-file audio offsets, and the new home shelf's stored name.
@MainActor
func registerAudioOffsetTests(_ t: TestRunner) async {
    t.suite("Audio offsets") { t in
        t.test("an offset is remembered per file, and zero forgets it") {
            let defaults = UserDefaults(suiteName: "audio-offset-test-\(UUID().uuidString)")!
            AudioOffsets.save(0.3, itemId: "a", defaults: defaults)
            t.expectEqual(AudioOffsets.saved(itemId: "a", defaults: defaults), 0.3)
            t.expectEqual(AudioOffsets.saved(itemId: "b", defaults: defaults), 0)
            AudioOffsets.save(0, itemId: "a", defaults: defaults)
            t.expectEqual(AudioOffsets.saved(itemId: "a", defaults: defaults), 0)
        }
    }
    t.suite("Continue the series shelf") { t in
        t.test("it survives being stored, and sits after Forgotten, under Next Up") {
            // Up Next leads now; Continue the Series still follows Forgotten.
            t.expectEqual(HomeSection(id: HomeSection.continueSeries.id), .continueSeries)
            let order = HomeOrder.defaultOrder(libraryIds: [])
            let forgotten = order.firstIndex(of: .forgotten)!
            t.expectEqual(order[forgotten + 1], .continueSeries)
        }
    }

    await t.suite("Most watched") { t in
        await t.test("collections order by the share of their titles watched") {
            let database = try LibraryDatabase(inMemory: true)
            try await database.writer.write { db in
                // half: 2 of 4 watched; all: 3 of 3; none: 0 of 5.
                for (id, members, unplayed) in [("half", 4, 2), ("all", 3, 0), ("none", 5, 5)] {
                    try db.execute(sql: """
                        INSERT INTO item (id, serverId, type, name, sortName, isFolder, childCount, syncedAt)
                        VALUES (?, 's', 'BoxSet', ?, ?, 1, ?, ?)
                        """, arguments: [id, id, id, members, Date()])
                    try db.execute(sql: """
                        INSERT INTO userData (itemId, played, unplayedItemCount, updatedAt) VALUES (?, 0, ?, ?)
                        """, arguments: [id, unplayed, Date()])
                }
            }
            let session = JellyfinSession(
                serverURL: URL(string: "http://127.0.0.1:9")!, serverName: "x",
                serverId: "s", userId: "u", userName: "u", deviceId: "d")
            let repository = LibraryRepository(
                database: database, client: JellyfinClient(session: session, token: "t"))
            let order = try await repository.entries(types: [.boxSet], sort: .watched, descending: true, limit: 10)
            t.expectEqual(order.map(\.id), ["all", "half", "none"])
        }
    }
}
