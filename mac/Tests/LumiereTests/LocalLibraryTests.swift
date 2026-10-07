import Foundation
import TestKit
import LumiereKit

/// The parts of the local-files feature that can be wrong quietly.
///
/// Identity above all. Every piece of state the app keeps about a file — watched,
/// resume position, favourite, subtitle offset, a generated thumbnail — is keyed to
/// the item id, so an id that changes between scans throws all of it away and the
/// library feels disposable. That is the property worth a test.
@MainActor
func registerLocalLibraryTests(_ t: TestRunner) {

    t.suite("Local library") { t in

        t.test("the same path always gives the same id") {
            let path = "/Volumes/Media/Anime/Show/Episode 01.mkv"
            t.expectEqual(LocalLibrary.id(for: path), LocalLibrary.id(for: path))
        }

        t.test("two names for one real file give one id") {
            // The bug the end-to-end test caught. `contentsOfDirectory` hands back
            // /private/var/... while a URL built by appending components keeps
            // /var/..., so a folder's own row and the rows inside it were hashed
            // from different strings — two ids for one file, and a Rescan that
            // could not find the folder it had just written.
            //
            // A real file, because that is the only case with an answer: symlink
            // resolution on a path that does not exist has nothing to resolve,
            // and every path the app hashes is one it has just walked or been
            // handed by a file chooser.
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumiere-alias-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true
            )
            let constructed = root.appendingPathComponent("clip.mkv")
            FileManager.default.createFile(atPath: constructed.path, contents: Data())
            defer { try? FileManager.default.removeItem(at: root) }

            let enumerated = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
            ))?.first
            t.expect(enumerated?.path != constructed.path,
                     "the two spellings must actually differ, or this proves nothing")
            t.expectEqual(
                LocalLibrary.id(for: constructed.path),
                LocalLibrary.id(for: enumerated?.path ?? "")
            )
        }

        t.test("different paths give different ids") {
            t.expect(
                LocalLibrary.id(for: "/a/b.mkv") != LocalLibrary.id(for: "/a/c.mkv"),
                "two files must not collide"
            )
        }

        t.test("a local id is recognisable as one") {
            t.expect(LocalLibrary.isLocal(itemId: LocalLibrary.id(for: "/a/b.mkv")),
                     "the prefix is how playback knows to skip the server")
            t.expect(!LocalLibrary.isLocal(itemId: "3e64483583ec1d71ea0851d6d144c4a6"),
                     "a Jellyfin id must never be taken for a local one")
        }

        t.test("a library id follows from its root and nothing else") {
            let root = "/Volumes/Media/Anime"
            t.expectEqual(
                LocalLibrary.libraryId(for: root), LocalLibrary.libraryId(for: root)
            )
            t.expect(
                LocalLibrary.libraryId(for: root) != LocalLibrary.id(for: root),
                "the library and the folder row must not share a primary key"
            )
        }

        t.test("the extension list covers what a real library holds") {
            for ext in ["mkv", "mp4", "avi", "m2ts", "webm", "ts"] {
                t.expect(LocalLibrary.videoExtensions.contains(ext), "\(ext) must be playable")
            }
            for ext in ["nfo", "srt", "jpg", "txt"] {
                t.expect(!LocalLibrary.videoExtensions.contains(ext),
                         "\(ext) is not a video and must not be listed as one")
            }
        }

        t.test("a folder walk finds files, folders and their parentage") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumiere-local-\(UUID().uuidString)")
            let season = root.appendingPathComponent("Season 1")
            try? FileManager.default.createDirectory(
                at: season, withIntermediateDirectories: true
            )
            FileManager.default.createFile(
                atPath: season.appendingPathComponent("Episode 01.mkv").path, contents: Data()
            )
            FileManager.default.createFile(
                atPath: season.appendingPathComponent("notes.txt").path, contents: Data()
            )
            defer { try? FileManager.default.removeItem(at: root) }

            let result = LocalLibraryScanner(root: root, libraryId: "lib").scan()
            t.expectEqual(result.fileCount, 1)

            let folder = result.records.first { $0.isFolder }
            let file = result.records.first { !$0.isFolder }
            t.expectEqual(folder?.name, "Season 1")
            t.expectEqual(file?.name, "Episode 01")
            // The file hangs off the folder, which is what lets the existing folder
            // browser walk a local library with no changes at all.
            t.expectEqual(file?.parentId, folder?.id)
            t.expectEqual(folder?.parentId, nil)
            t.expectEqual(file?.libraryId, "lib")
        }
    }
}
