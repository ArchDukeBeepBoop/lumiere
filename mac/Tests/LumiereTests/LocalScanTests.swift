import Foundation
import TestKit
import LumiereKit
import GRDB

/// The local-files feature end to end: a real folder, a real repository, a real
/// database.
///
/// The scanner has its own unit tests; this covers the part those cannot — that a
/// folder becomes rows the *rest of the app* can use. Every claim made for the
/// feature depends on that: the browser walks by `parentId`, the sidebar reads
/// `libraries()`, playback resolves a file through `localFile(for:)`, and a rescan
/// must not throw away the watch state keyed to an item id.
@MainActor
func registerLocalScanTests(_ t: TestRunner) async {

    func makeRepository() throws -> LibraryRepository {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!,
            serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        // Never reached: nothing about a local folder involves a server.
        let client = JellyfinClient(session: session, token: "t")
        return LibraryRepository(database: database, client: client)
    }

    /// A throwaway folder holding one season of one show plus a stray file.
    func makeFolder() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumiere-scan-\(UUID().uuidString)")
        let season = root.appendingPathComponent("Season 1")
        try? FileManager.default.createDirectory(at: season, withIntermediateDirectories: true)
        for name in ["Episode 01.mkv", "Episode 02.mkv", "poster.jpg"] {
            FileManager.default.createFile(
                atPath: season.appendingPathComponent(name).path, contents: Data()
            )
        }
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("Trailer.mp4").path, contents: Data()
        )
        return root
    }

    await t.suite("Local scan, end to end") { t in

        await t.test("a folder becomes a library the sidebar can list") {
            let repository = try makeRepository()
            let root = makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }

            let summary = try await repository.scanLocalFolder(at: root)
            t.expectEqual(summary.fileCount, 3)
            t.expect(summary.unreadable.isEmpty, "nothing should have been unreadable")

            let libraries = try await repository.libraries()
            t.expectEqual(libraries.count, 1)
            t.expectEqual(libraries.first?.name, root.lastPathComponent)
            // No collection type is what routes it to the folder browser rather
            // than to a grid of matched titles.
            t.expectEqual(libraries.first?.collectionType, nil)
            t.expectEqual(libraries.first?.prefersFolderBrowsing, true)
        }

        await t.test("browsing walks the tree the way the folder browser does") {
            let repository = try makeRepository()
            let root = makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let summary = try await repository.scanLocalFolder(at: root)

            // The browser's own entry point for a library root.
            let top = try await repository.libraryRootChildren(libraryId: summary.libraryId)
            t.expectEqual(Set(top.map(\.item.name)), ["Season 1", "Trailer"])

            guard let season = top.first(where: { $0.item.isFolder }) else {
                t.expect(false, "the season folder must be listed")
                return
            }
            let episodes = try await repository.folderChildren(parentId: season.id)
            t.expectEqual(episodes.map(\.item.name).sorted(), ["Episode 01", "Episode 02"])
            // The image alongside them is not a video and must not be listed.
            t.expect(!episodes.contains { $0.item.name == "poster" }, "no stray images")
        }

        await t.test("playback can resolve a file, and refuses one that is gone") {
            let repository = try makeRepository()
            let root = makeFolder()
            let summary = try await repository.scanLocalFolder(at: root)

            let id = LocalLibrary.id(for: root.appendingPathComponent("Trailer.mp4").path)
            let url = try await repository.localFile(for: id)
            t.expectEqual(url?.lastPathComponent, "Trailer.mp4")

            // An unmounted drive leaves every path intact and every file gone.
            try? FileManager.default.removeItem(at: root)
            let missing = try await repository.localFile(for: id)
            t.expect(missing == nil, "a file that is no longer there must not be played")
            t.expectEqual(summary.name, root.lastPathComponent)
        }

        await t.test("a rescan keeps watch state and drops deleted files") {
            let repository = try makeRepository()
            let root = makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            // Discarded on purpose: this test is about what the *second* scan does
            // to the rows the first one wrote.
            _ = try await repository.scanLocalFolder(at: root)

            let episode = root.appendingPathComponent("Season 1/Episode 01.mkv")
            let id = LocalLibrary.id(for: episode.path)
            try await repository.applyLocalProgress(itemId: id, positionSeconds: 615)

            // A file removed between scans.
            try? FileManager.default.removeItem(
                at: root.appendingPathComponent("Season 1/Episode 02.mkv")
            )
            let second = try await repository.scanLocalFolder(at: root)
            t.expectEqual(second.fileCount, 2)

            let entry = try await repository.entry(id: id)
            // The whole reason ids are derived from paths rather than allocated.
            t.expectEqual(entry?.userData?.resumeSeconds, 615)

            let gone = LocalLibrary.id(
                for: root.appendingPathComponent("Season 1/Episode 02.mkv").path
            )
            let goneEntry = try await repository.entry(id: gone)
            t.expect(goneEntry == nil, "a deleted file must stop being listed")
        }

        await t.test("removing a folder takes its rows and nothing else") {
            let repository = try makeRepository()
            let root = makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let summary = try await repository.scanLocalFolder(at: root)

            try await repository.removeLocalLibrary(id: summary.libraryId)
            t.expectEqual(try await repository.libraries().count, 0)
            t.expectEqual(
                try await repository.libraryRootChildren(libraryId: summary.libraryId).count, 0
            )
        }

        await t.test("a private library disappears from cross-library reads") {
            let repository = try makeRepository()
            let root = makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let summary = try await repository.scanLocalFolder(at: root)

            // Named explicitly: still visible, because that is a deliberate visit.
            await repository.setPrivateLibraryIds([summary.libraryId])
            t.expect(
                try await repository.libraryRootChildren(libraryId: summary.libraryId).count > 0,
                "opening a private library must still work"
            )

            // Not named: gone, and the search that would have surfaced it too.
            let searched = try await repository.entries(
                types: [], limit: 50, offset: 0, searchTerm: "Trailer"
            )
            t.expect(
                !searched.contains { $0.item.name == "Trailer" },
                "a private library must not appear in a search for something in it"
            )
        }
    }
}
