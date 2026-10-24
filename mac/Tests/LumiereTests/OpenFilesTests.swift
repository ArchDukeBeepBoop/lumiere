import Foundation
import TestKit
import LumiereKit

/// Opening files, folders, streams and playlists directly — the "On This
/// Computer" door. What matters is that each becomes rows the player can
/// resolve, that Next walks the folder in Finder's order, and that a list of
/// channels keeps the list's order.
@MainActor
func registerOpenFilesTests(_ t: TestRunner) async {

    func makeRepository() throws -> LibraryRepository {
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!, serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        return LibraryRepository(
            database: try LibraryDatabase(inMemory: true),
            client: JellyfinClient(session: session, token: "t")
        )
    }

    func makeSeason() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumiere-open-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Created out of order, and with 10 after 9: Finder order is 1, 2, 9, 10.
        for name in ["Show 10.mkv", "Show 2.mkv", "Show 1.mkv", "Show 9.mkv", "notes.txt", "Theme.flac"] {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        return root
    }

    await t.suite("Opening files directly") { t in

        await t.test("one file plays, and its folder is Next and Previous in Finder's order") {
            let repository = try makeRepository()
            let root = makeSeason()
            defer { try? FileManager.default.removeItem(at: root) }

            let ids = try await repository.openLocal([root.appendingPathComponent("Show 2.mkv")])
            t.expectEqual(ids.count, 1)
            let file = try await repository.localFile(for: ids[0])
            t.expectEqual(file?.lastPathComponent, "Show 2.mkv")

            let siblings = try await repository.localSiblings(of: ids[0])
            t.expectEqual(siblings.map(\.item.name), ["Show 1", "Show 2", "Show 9", "Show 10", "Theme"])
        }

        await t.test("opening never adds a sidebar library") {
            let repository = try makeRepository()
            let root = makeSeason()
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try await repository.openLocal([root.appendingPathComponent("Show 1.mkv")])
            let local = try await repository.localLibraries()
            t.expect(local.isEmpty, "opened files must not appear as an added folder")
        }

        await t.test("a folder plays from its first file") {
            let repository = try makeRepository()
            let root = makeSeason()
            defer { try? FileManager.default.removeItem(at: root) }
            let ids = try await repository.openLocal([root])
            t.expectEqual(ids.count, 5)
            let first = try await repository.localFile(for: ids[0])
            t.expectEqual(first?.lastPathComponent, "Show 1.mkv")
        }

        await t.test("a file already in an added folder keeps that folder's library") {
            let repository = try makeRepository()
            let root = makeSeason()
            defer { try? FileManager.default.removeItem(at: root) }
            let summary = try await repository.scanLocalFolder(at: root)
            let ids = try await repository.openLocal([root.appendingPathComponent("Show 9.mkv")])
            let entry = try await repository.entry(id: ids[0])
            t.expectEqual(entry?.item.libraryId, summary.libraryId)
        }

        await t.test("a stream address resolves to itself") {
            let repository = try makeRepository()
            let url = URL(string: "https://example.com/live/channel.m3u8")!
            let ids = try await repository.openStream(url)
            t.expectEqual(ids.count, 1)
            let resolved = try await repository.localFile(for: ids[0])
            t.expectEqual(resolved, url)
        }

        await t.test("a playlist file becomes its channels, in the list's order") {
            let repository = try makeRepository()
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumiere-\(UUID().uuidString).m3u")
            defer { try? FileManager.default.removeItem(at: file) }
            try """
            #EXTM3U
            #EXTINF:-1 tvg-id="z" group-title="News, World",Zulu News
            http://example.com/z.ts
            #EXTINF:-1,Alpha Sports
            http://example.com/a.ts
            """.write(to: file, atomically: true, encoding: .utf8)

            let ids = try await repository.openStream(file)
            t.expectEqual(ids.count, 2)
            let siblings = try await repository.localSiblings(of: ids[0])
            t.expectEqual(siblings.map(\.item.name), ["Zulu News", "Alpha Sports"])
        }
    }

    t.suite("M3U parsing") { t in
        t.test("titles come after the last comma outside quotes") {
            let entries = StreamPlaylist.parse("""
            #EXTM3U
            #EXTINF:-1 group-title="A, B",Channel One
            http://x/1
            http://x/two.ts
            """)
            t.expectEqual(entries.map(\.title), ["Channel One", "two"])
            t.expectEqual(entries.map(\.url.absoluteString), ["http://x/1", "http://x/two.ts"])
        }
        t.test("relative entries resolve against the list") {
            let entries = StreamPlaylist.parse("seg/one.ts\n", base: URL(string: "http://host/list.m3u")!)
            t.expectEqual(entries.first?.url.absoluteString, "http://host/seg/one.ts")
        }
        t.test("a remote .m3u8 is one HLS stream, not a list") {
            t.expect(!StreamPlaylist.isPlaylist(URL(string: "https://h/live.m3u8")!), "HLS plays as one stream")
            t.expect(StreamPlaylist.isPlaylist(URL(fileURLWithPath: "/tmp/tv.m3u8")), "a file on disk is a list")
            t.expect(StreamPlaylist.isPlaylist(URL(string: "https://h/tv.m3u")!), "an .m3u is a list")
        }
        t.test("only real stream schemes count") {
            t.expect(StreamPlaylist.isStream(URL(string: "rtsp://cam/1")!), "rtsp")
            t.expect(!StreamPlaylist.isStream(URL(string: "javascript:alert(1)")!), "not a stream")
            t.expect(!StreamPlaylist.isStream(URL(fileURLWithPath: "/a.mkv")), "a file is not a stream")
        }
    }
}
