import Foundation
import TestKit
import LumiereKit

/// Which libraries a sync reads.
///
/// Worth pinning rather than eyeballing, because every failure mode here is silent.
/// A selection that resolves to nothing produces a sync that "succeeds" instantly; a
/// selection that lets a music library through recurses into every track; and a
/// selection stored as inclusions rather than exclusions means a library added on
/// the server next month is never scanned at all, with no symptom except stale rows
/// — which is the complaint this whole feature exists to answer.
@MainActor
func registerSyncSelectionTests(_ t: TestRunner) {

    /// A library record, which has no memberwise initialiser of its own.
    func library(_ id: String, _ name: String, type: String?) -> LibraryRecord {
        var record = LibraryRecord(
            from: try! JellyfinClient.decoder.decode(
                JellyfinItem.self,
                from: try! JSONSerialization.data(withJSONObject: [
                    "Id": id, "Name": name, "Type": "CollectionFolder",
                ] as [String: Any])
            ),
            serverId: "s1", sortIndex: 0
        )
        record.collectionType = type
        return record
    }

    let all = [
        library("movies", "Movies", type: "movies"),
        library("shows", "TV Shows", type: "tvshows"),
        library("anime", "Anime", type: "tvshows"),
        library("music", "Music", type: "music"),
        library("lists", "Playlists", type: "playlists"),
    ]

    t.suite("Sync selection") { t in

        t.test("everything playable is scanned by default") {
            let selection = SyncSelection()
            t.expectEqual(selection.libraries(from: all).map(\.id), ["movies", "shows", "anime"])
            t.expectEqual(selection.depth, .quick)
        }

        t.test("music and playlists are never offered to the sync loop") {
            // Not cosmetic: syncLibrary recurses, so a music library reaching the
            // loop pulls in every track — unbounded work for a video player that
            // cannot play one of them.
            var selection = SyncSelection()
            selection.excludedLibraryIds = []
            let ids = selection.libraries(from: all).map(\.id)
            t.expect(!ids.contains("music"))
            t.expect(!ids.contains("lists"))
        }

        t.test("unticking a library removes it from the pass") {
            var selection = SyncSelection()
            selection.setIncluded(false, for: "anime")
            t.expect(!selection.includes("anime"))
            t.expectEqual(selection.libraries(from: all).map(\.id), ["movies", "shows"])
        }

        t.test("re-ticking puts it back") {
            var selection = SyncSelection(excludedLibraryIds: ["anime"])
            selection.setIncluded(true, for: "anime")
            t.expect(selection.includes("anime"))
            t.expectEqual(selection.libraries(from: all).count, 3)
        }

        t.test("a library added later is scanned without being ticked") {
            // The reason exclusions are stored rather than inclusions. With
            // inclusions, a library added on the server after the last time anyone
            // opened the panel would silently never sync.
            let selection = SyncSelection(excludedLibraryIds: ["anime"])
            let withNewLibrary = all + [library("docs", "Documentaries", type: "movies")]
            t.expect(selection.libraries(from: withNewLibrary).map(\.id).contains("docs"))
        }

        t.test("unticking everything resolves to nothing") {
            // The sync loop checks for this and returns rather than reporting a
            // completed pass over zero libraries.
            var selection = SyncSelection()
            for record in all { selection.setIncluded(false, for: record.id) }
            t.expect(selection.libraries(from: all).isEmpty)
        }
    }

    t.suite("Sync selection storage") { t in

        /// An isolated defaults domain, so the suite cannot read or clobber the
        /// real app's stored choice on this machine.
        func scratchDefaults(_ name: String) -> UserDefaults {
            let defaults = UserDefaults(suiteName: "lumiere.tests.\(name)")!
            defaults.removePersistentDomain(forName: "lumiere.tests.\(name)")
            return defaults
        }

        t.test("a saved selection comes back") {
            let defaults = scratchDefaults("roundtrip")
            SyncSelection(depth: .full, excludedLibraryIds: ["anime", "movies"])
                .save(to: defaults)
            let loaded = SyncSelection.load(from: defaults)
            t.expectEqual(loaded.depth, .full)
            t.expectEqual(loaded.excludedLibraryIds, ["anime", "movies"])
        }

        t.test("nothing stored means everything, quickly") {
            // This is what a first run gets, and it has to match the behaviour the
            // app had before the panel existed.
            let loaded = SyncSelection.load(from: scratchDefaults("empty"))
            t.expectEqual(loaded.depth, .quick)
            t.expect(loaded.excludedLibraryIds.isEmpty)
        }

        t.test("an unreadable depth falls back rather than throwing") {
            let defaults = scratchDefaults("garbage")
            defaults.set("thorough", forKey: "sync.depth")
            t.expectEqual(SyncSelection.load(from: defaults).depth, .quick)
        }

        t.test("the stored exclusion list is stable between writes") {
            // A Set's iteration order is not, and an unstable plist value makes any
            // diff of the defaults file useless for checking what was remembered.
            let defaults = scratchDefaults("stable")
            SyncSelection(excludedLibraryIds: ["c", "a", "b"]).save(to: defaults)
            t.expectEqual(defaults.stringArray(forKey: "sync.excludedLibraryIds"), ["a", "b", "c"])
        }
    }
}
