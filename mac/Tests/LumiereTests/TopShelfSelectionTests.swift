import Foundation
import TestKit
import LumiereKit

/// Which libraries each Top 10 row ranks, once the owner has said.
///
/// Pinned because the guess it overrides was wrong twice on a real server, and both
/// times silently: the adult library is `tvshows`, its name says nothing about
/// anime, and its age ratings are indistinguishable from television's. A stored
/// choice has to beat every inference, including the one about privacy.
@MainActor
func registerTopShelfSelectionTests(_ t: TestRunner) async {

    func library(_ id: String, _ name: String, _ type: String?) -> LibraryRecord {
        LibraryRecord(
            id: id, serverId: "s1", name: name,
            collectionType: type, sortIndex: 0, itemCount: nil
        )
    }

    let libraries = [
        library("tv", "TV Shows", "tvshows"),
        library("anime", "Anime", "tvshows"),
        library("hobby", "Hobby TV", "tvshows"),
        library("adult", "Adult", "tvshows"),
        library("movies", "Movies", "movies"),
        library("music", "Music", "music"),
    ]

    // A fresh domain per test, so one test's stored choice cannot leak into another.
    func clearAll() {
        for kind in LibraryKinds.Kind.allCases { TopShelfSelection.clear(kind) }
    }

    t.suite("Top 10 selection") { t in

        t.test("with no choice stored it falls back to the guess") {
            clearAll()
            let ids = TopShelfSelection.libraryIds(
                for: .series, in: libraries, excluding: []
            )
            // The guess cannot tell television from the adult library, which is the
            // whole reason the choice exists.
            t.expectEqual(ids, ["tv", "hobby", "adult"])
        }

        t.test("a stored choice wins over the guess") {
            clearAll()
            TopShelfSelection.store(["tv"], for: .series)
            let ids = TopShelfSelection.libraryIds(
                for: .series, in: libraries, excluding: []
            )
            t.expectEqual(ids, ["tv"])
            clearAll()
        }

        t.test("a stored choice beats the privacy default too") {
            // Ticking a library by hand is a more specific instruction than any
            // default about what should be hidden.
            clearAll()
            TopShelfSelection.store(["tv", "adult"], for: .series)
            let ids = TopShelfSelection.libraryIds(
                for: .series, in: libraries, excluding: ["adult"]
            )
            t.expect(ids.contains("adult"))
            clearAll()
        }

        t.test("unticking everything means none, not 'never chosen'") {
            // The distinction that makes the card work: if empty fell back to the
            // guess, unticking the last library would restore all four.
            clearAll()
            TopShelfSelection.store([], for: .series)
            let ids = TopShelfSelection.libraryIds(
                for: .series, in: libraries, excluding: []
            )
            t.expect(ids.isEmpty, "got \(ids)")
            clearAll()
        }

        t.test("a library removed from the server drops out of a stored choice") {
            clearAll()
            TopShelfSelection.store(["tv", "deleted"], for: .series)
            let ids = TopShelfSelection.libraryIds(
                for: .series, in: libraries, excluding: []
            )
            t.expectEqual(ids, ["tv"], "a dead id must not reach the query")
            clearAll()
        }

        t.test("the order follows the sidebar, not the tick order") {
            clearAll()
            TopShelfSelection.store(["hobby", "tv"], for: .series)
            let ids = TopShelfSelection.libraryIds(
                for: .series, in: libraries, excluding: []
            )
            t.expectEqual(ids, ["tv", "hobby"])
            clearAll()
        }

        t.test("only rankable libraries are offered") {
            // Music carries no community ratings, so it is not a candidate however
            // the owner feels about it.
            let names = TopShelfSelection.candidates(in: libraries).map(\.name)
            t.expect(!names.contains("Music"))
            t.expect(names.contains("Adult"), "the guess left it out; the list must not")
        }
    }
}
