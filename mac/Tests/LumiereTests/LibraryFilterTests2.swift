import Foundation
import TestKit
import LumiereKit
import GRDB

/// The second half of the library filter tests. Split for the 300-line rule.
@MainActor
func registerLibraryFilterTests2(_ t: TestRunner) async {
    await t.suite("Library filters, continued") { t in
        t.test("seasons with no number sort to the back rather than crashing the order") {
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
            let ordered = [season(nil, "Extras"), season(1, "Season 1")].orderedAsSeasons
            t.expectEqual(ordered.map(\.item.name), ["Season 1", "Extras"])
        }

        await t.test("the prefetch cursor survives and can be cleared") {
            // The whole point: a twenty-minute job that loses its place on every quit
            // is a job that never finishes.
            let (repository, _) = try makeRepository()
            t.expect(try await repository.prefetchCursor() == nil)

            try await repository.setPrefetchCursor("item-500")
            t.expectEqual(try await repository.prefetchCursor(), "item-500")

            // Cleared on completion, so the next run starts over rather than believing
            // it has nothing left to do — new items arrive.
            try await repository.setPrefetchCursor(nil)
            t.expect(try await repository.prefetchCursor() == nil)
        }

        await t.test("the cursor is overwritten, not accumulated") {
            let (repository, _) = try makeRepository()
            try await repository.setPrefetchCursor("a")
            try await repository.setPrefetchCursor("b")
            t.expectEqual(try await repository.prefetchCursor(), "b")
        }

        await t.test("artwork targets come back in a stable order") {
            // The cursor is a position in this list. An order that shifts between runs
            // would silently skip or repeat items.
            let (repository, database) = try makeRepository()
            for id in ["c", "a", "b"] {
                try insert(database, id: id, name: id.uppercased())
            }
            let first = try await repository.artworkTargets().map(\.itemId)
            let second = try await repository.artworkTargets().map(\.itemId)
            t.expectEqual(first, second)
            t.expectEqual(first, first.sorted())
        }

        t.test("libraries with no collection type prefer folder browsing") {
            // The 3D and My Videos case: Jellyfin never identified the contents, so
            // there is no metadata for a grid to arrange.
            func library(_ type: String?) -> LibraryRecord {
                var record = LibraryRecord(
                    from: try! JellyfinClient.decoder.decode(
                        JellyfinItem.self,
                        from: try! JSONSerialization.data(withJSONObject: [
                            "Id": "l", "Name": "L", "Type": "CollectionFolder",
                        ] as [String: Any])
                    ),
                    serverId: "s1", sortIndex: 0
                )
                record.collectionType = type
                return record
            }

            t.expect(library(nil).prefersFolderBrowsing)
            t.expect(library("").prefersFolderBrowsing)
            t.expect(library("homevideos").prefersFolderBrowsing)
            // Identified libraries keep the metadata grid.
            t.expect(!library("movies").prefersFolderBrowsing)
            t.expect(!library("tvshows").prefersFolderBrowsing)
        }

        await t.test("folder children come back folders first, then files by name") {
            // How every file browser on the platform behaves, and the point of this
            // mode is to look like the folders on disk.
            let (repository, database) = try makeRepository()
            try insert(database, id: "zfolder", name: "Zed Folder", parentId: "root")
            try insert(database, id: "afile", name: "A File", parentId: "root")
            try await database.writer.write { db in
                try db.execute(sql: "UPDATE item SET isFolder = 1 WHERE id = 'zfolder'")
                try db.execute(sql: "UPDATE item SET parentId = 'root' WHERE id IN ('zfolder','afile')")
            }

            let children = try await repository.folderChildren(parentId: "root")
            t.expectEqual(children.map(\.item.name), ["Zed Folder", "A File"])
        }

        await t.test("no favourites is an empty list, not an error") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "A")
            t.expect(try await repository.favouriteEntries().isEmpty)
        }

        await t.test("the jump rail is built from the library, not the loaded page") {
            // The bug this pins: anchors derived from a grid's first page meant
            // every letter past it pointed at nothing, and the rail appeared to
            // wake up only once paging happened to reach those rows.
            let (repository, database) = try makeRepository()
            for (index, name) in ["Akira", "Berserk", "Cowboy Bebop", "Zeta"].enumerated() {
                try insert(database, id: "\(index)", name: name)
            }
            let anchors = try await repository.alphabetAnchors(
                libraryId: "lib", types: [.movie]
            )
            t.expectEqual(anchors.map(\.letter), ["A", "B", "C", "Z"])
            // The offset is what turns a letter into "load this far first".
            t.expectEqual(anchors.last?.offset, 3)
        }

        await t.test("each letter anchors on its first title, not a later one") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Akira")
            try insert(database, id: "2", name: "Angel Beats")
            let anchors = try await repository.alphabetAnchors(
                libraryId: "lib", types: [.movie]
            )
            t.expectEqual(anchors.count, 1)
            t.expectEqual(anchors.first?.id, "1")
        }

        await t.test("digits and non-Latin titles anchor under #") {
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "3x3 Eyes")
            try insert(database, id: "2", name: "Akira")
            let anchors = try await repository.alphabetAnchors(
                libraryId: "lib", types: [.movie]
            )
            t.expectEqual(anchors.first?.letter, "#")
        }

        await t.test("a private library's years stay out of the filter menu") {
            // The menu is a promise that picking a year shows something. Without
            // the same exclusions the grid uses it listed years belonging only to
            // items the grid will not draw — a dead entry that also says the year
            // is in the collection somewhere.
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Public", year: 2001, parentId: "lib")
            try insert(database, id: "2", name: "Private", year: 1974, parentId: "vault")

            t.expectEqual(try await repository.years(), [2001, 1974])
            await repository.setPrivateLibraryIds(["vault"])
            t.expectEqual(try await repository.years(), [2001])
            // Still listed when that library is the one being looked at, which is a
            // deliberate visit rather than a leak.
            t.expectEqual(try await repository.years(libraryId: "vault"), [1974])
        }

        await t.test("no rail outside name order, where a letter means nothing") {
            // In date-added order the letters are scattered, and a jump would land
            // somewhere arbitrary — so this returns nothing rather than lying.
            let (repository, database) = try makeRepository()
            try insert(database, id: "1", name: "Akira")
            let anchors = try await repository.alphabetAnchors(
                libraryId: "lib", types: [.movie], sort: .dateAdded
            )
            t.expectEqual(anchors.count, 0)
        }
    }
}
