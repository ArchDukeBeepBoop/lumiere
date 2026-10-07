import Foundation
import TestKit
import LumiereKit
import GRDB

/// The private room: inside, only its libraries; outside, never them.
@MainActor
func registerRoomTests(_ t: TestRunner) async {
    await t.suite("Private room") { t in
        await t.test("inside, lists hold only the room's libraries; outside, none of them") {
            let database = try LibraryDatabase(inMemory: true)
            try await database.writer.write { db in
                for (id, library) in [("film", "main"), ("clip", "private")] {
                    try db.execute(sql: """
                        INSERT INTO item (id, serverId, type, name, sortName, libraryId, isFolder, syncedAt)
                        VALUES (?, 's', 'Movie', ?, ?, ?, 0, ?)
                        """, arguments: [id, id, id, library, Date()])
                }
            }
            let session = JellyfinSession(
                serverURL: URL(string: "http://127.0.0.1:9")!, serverName: "x",
                serverId: "s", userId: "u", userName: "u", deviceId: "d")
            let repository = LibraryRepository(
                database: database, client: JellyfinClient(session: session, token: "t"))
            await repository.setPrivateLibraryIds(["private"])
            t.expectEqual(try await repository.entries(types: [.movie], limit: 10).map(\.id), ["film"])
            await repository.setPrivateLibraryIds([])
            await repository.setRoomLibraryIds(["private"])
            t.expectEqual(try await repository.entries(types: [.movie], limit: 10).map(\.id), ["clip"])
        }
    }
}

@MainActor
func registerRoomPreferenceTests(_ t: TestRunner) async {
    t.suite("Room settings") { t in
        t.test("each room keeps its own, and the first visit starts from the library's") {
            let d = UserDefaults.standard
            RoomPreferences.recoverAtLaunch()
            d.set("hero", forKey: "homeLayout")
            d.set(true, forKey: "homeShowsBackdrop")
            RoomPreferences.enter()
            t.expectEqual(d.string(forKey: "homeLayout"), "hero")
            d.set("compact", forKey: "homeLayout")
            d.set(false, forKey: "homeShowsBackdrop")
            RoomPreferences.leave()
            t.expectEqual(d.string(forKey: "homeLayout"), "hero")
            t.expectEqual(d.bool(forKey: "homeShowsBackdrop"), true)
            RoomPreferences.enter()
            t.expectEqual(d.string(forKey: "homeLayout"), "compact")
            t.expectEqual(d.bool(forKey: "homeShowsBackdrop"), false)
            RoomPreferences.recoverAtLaunch()
            t.expectEqual(d.string(forKey: "homeLayout"), "hero")
            for key in ["homeLayout", "homeShowsBackdrop", "roomPreferences.library", "roomPreferences.room",
                        "roomPreferencesActive"] { d.removeObject(forKey: key) }
        }
    }
}
