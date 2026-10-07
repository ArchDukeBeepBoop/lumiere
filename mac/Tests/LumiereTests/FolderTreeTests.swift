import Foundation
import TestKit
import LumiereKit

/// What a directory listing contains, given the paths beneath it.
///
/// Pinned because the browser keys on paths now rather than on Jellyfin's ParentId,
/// and the two disagree: on the `3D` library fifteen rows had a parent whose own
/// path was not their containing directory, and `Clips/Northwind` had no cached
/// row at all while holding a file. Both cases are here.
@MainActor
func registerFolderTreeTests(_ t: TestRunner) async {
    let root = "/Volumes/M/3D/Games"

    t.suite("Folder tree") { t in

        t.test("direct files are listed and deeper ones are not") {
            let listing = FolderTree.listing(of: root, paths: [
                "\(root)/loose.mkv",
                "\(root)/Northwind/one.mkv",
            ])
            t.expectEqual(listing.files, ["\(root)/loose.mkv"])
        }

        t.test("a folder with no item of its own still appears") {
            // The case that started this. Jellyfin collapses a directory holding a
            // single video into a Movie item, so the directory is never reported —
            // and keying only on cached rows left the file nowhere to be shown.
            let listing = FolderTree.listing(of: root, paths: [
                "\(root)/Northwind/one.mkv",
            ])
            t.expectEqual(listing.folders, ["\(root)/Northwind"])
        }

        t.test("a folder holding many files is still one folder") {
            let listing = FolderTree.listing(of: root, paths: [
                "\(root)/Lantern Road/a.mkv",
                "\(root)/Lantern Road/b.mkv",
                "\(root)/Lantern Road/c.mkv",
            ])
            t.expectEqual(listing.folders, ["\(root)/Lantern Road"])
        }

        t.test("grandchildren contribute their own folder, not themselves") {
            let listing = FolderTree.listing(of: root, paths: [
                "\(root)/Quiet House/Remakes/two.mkv",
            ])
            t.expectEqual(listing.folders, ["\(root)/Quiet House"])
            t.expect(listing.files.isEmpty)
        }

        t.test("a sibling folder sharing a name prefix is not swept in") {
            // `Games2` must not be read as a child of `Games`. This is the same
            // mistake the SQL range made in the other direction.
            let listing = FolderTree.listing(of: root, paths: [
                "\(root)/a.mkv",
                "/Volumes/M/3D/Games2/b.mkv",
            ])
            t.expectEqual(listing.files, ["\(root)/a.mkv"])
            t.expect(listing.folders.isEmpty)
        }

        t.test("the folder itself is not listed inside itself") {
            let listing = FolderTree.listing(of: root, paths: [root, "\(root)/a.mkv"])
            t.expectEqual(listing.files, ["\(root)/a.mkv"])
        }

        t.test("a trailing separator on the folder changes nothing") {
            let withSlash = FolderTree.listing(of: root + "/", paths: ["\(root)/a.mkv"])
            let without = FolderTree.listing(of: root, paths: ["\(root)/a.mkv"])
            t.expectEqual(withSlash, without)
        }

        t.test("folders sort the way a file browser sorts them") {
            let listing = FolderTree.listing(of: root, paths: [
                "\(root)/Lantern Road/a.mkv",
                "\(root)/Far Horizon/b.mkv",
                "\(root)/Northwind/c.mkv",
            ])
            t.expectEqual(listing.folders.map { FolderTree.name(of: $0) },
                          ["Far Horizon", "Lantern Road", "Northwind"])
        }
    }
}

/// The files Jellyfin folded into a neighbour, standing on their own.
///
/// Pinned because the failure is silent and subtractive: the server returns one item
/// where the owner put ten files, so nothing errors and nothing looks broken — the
/// folder is simply nine files short. Measured on `3D`, each
/// `Clips/Compilations/…` folder returned one item against `Clips/Lantern Road`'s
/// seven.
@MainActor
func registerMergedFileTests(_ t: TestRunner) async {
    let folder = "/Volumes/M/3D/Clips/Compilations/Sample Uploader Collection"

    t.suite("Merged files") { t in

        t.test("a merged file names the item it plays through") {
            let version = ItemVersionRecord(
                itemId: "owner", sourceId: "src2",
                path: "\(folder)/second.mp4", name: "second.mp4"
            )
            let record = ItemRecord.mergedFile(version: version, libraryId: "lib")
            t.expectEqual(record.mergedOwnerId, "owner")
            // The id is the *source*, which is what playback selects with.
            t.expectEqual(record.id, "src2")
            t.expectEqual(record.path, "\(folder)/second.mp4")
        }

        t.test("an ordinary row has no owner and plays as itself") {
            var record = ItemRecord.mergedFile(
                version: ItemVersionRecord(
                    itemId: "owner", sourceId: "src", path: nil, name: "x"
                ),
                libraryId: "lib"
            )
            // What the server returned carries a real serverId.
            record.serverId = "s1"
            t.expectNil(record.mergedOwnerId, "a synced row must never be redirected")
        }

        t.test("a synthesised folder is not mistaken for a merged file") {
            let record = ItemRecord.syntheticFolder(path: folder, libraryId: "lib")
            t.expectNil(record.mergedOwnerId)
            t.expect(record.isFolder)
        }

        t.test("a nameless source falls back to its filename") {
            let version = ItemVersionRecord(
                itemId: "owner", sourceId: "src", path: "\(folder)/third.mp4", name: nil
            )
            t.expectEqual(ItemRecord.mergedFile(version: version, libraryId: nil).name,
                          "third.mp4")
        }

        t.test("the merged files list beside the item that swallowed them") {
            // The owner keeps its own row and its own path is one of the sources, so
            // the listing must not show that first file twice.
            let owner = "\(folder)/first.mp4"
            let listing = FolderTree.listing(of: folder, paths: [
                owner, "\(folder)/second.mp4", "\(folder)/third.mp4",
            ])
            t.expectEqual(listing.files.sorted(),
                          [owner, "\(folder)/second.mp4", "\(folder)/third.mp4"].sorted())
        }

        t.test("a cached sub-folder is a folder, not a file with the same id") {
            // What the wall actually showed: `Games` held 21 directories, sixteen of
            // which the server had given rows for. Each of those sixteen arrived
            // twice — once synthesised from the files beneath it, once from its own
            // path, which is one level down and so looks exactly like a file. 37
            // tiles for 21 folders, and the duplicates drew as blank cells.
            let cached = "\(folder)/Lantern Road"
            let listing = FolderTree.listing(
                of: folder,
                paths: [cached, "\(folder)/Lantern Road/one.mp4", "\(folder)/loose.mp4"],
                directories: [cached]
            )
            t.expectEqual(listing.folders, [cached])
            t.expectEqual(listing.files, ["\(folder)/loose.mp4"])
        }

        t.test("a folder with no cached row of its own still appears") {
            // The other half, unchanged: naming the directories must not stop one
            // being synthesised from the files inside it.
            let listing = FolderTree.listing(
                of: folder, paths: ["\(folder)/Northwind/one.mp4"], directories: []
            )
            t.expectEqual(listing.folders, ["\(folder)/Northwind"])
            t.expect(listing.files.isEmpty)
        }
    }
}
