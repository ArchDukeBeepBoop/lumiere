import Foundation
import TestKit
import LumiereKit

/// Matching a typed term against a title.
///
/// Every case here comes from a search that failed on the real library. Case was
/// never the problem — SQLite's LIKE is already case-insensitive — but punctuation,
/// word order and scope all were, and each looked like the app not finding
/// something plainly there.
@MainActor
func registerSearchKeyTests(_ t: TestRunner) {

    t.suite("Search matching") { t in

        t.test("punctuation stops mattering") {
            // "fate zero" returned nothing, because the title is Fate/Zero and a
            // slash is not a space.
            let key = SearchKey.key(name: "Fate/Zero", seriesName: nil)
            t.expect(SearchKey.matches(term: "fate zero", key: key), "space finds the slash")
            t.expect(SearchKey.matches(term: "Fate/Zero", key: key), "so does the slash")
            t.expect(SearchKey.matches(term: "FATE", key: key), "and case never mattered")
        }

        t.test("words may arrive in any order") {
            // "academy sky" returned nothing: a substring has to be contiguous.
            let key = SearchKey.key(name: "Sky Wizards Academy", seriesName: nil)
            t.expect(SearchKey.matches(term: "academy sky", key: key), "reversed still matches")
            t.expect(SearchKey.matches(term: "sky academy", key: key), "gaps are fine too")
        }

        t.test("every word must appear, not just one") {
            // An OR would return most of the library for any two-word query.
            let key = SearchKey.key(name: "Sky Wizards Academy", seriesName: nil)
            t.expect(!SearchKey.matches(term: "sky dog", key: key), "one miss is a miss")
        }

        t.test("an episode is findable by its show") {
            // The old query searched the item's own name only, so this failed.
            let key = SearchKey.key(
                name: "The Strongest Traitor", seriesName: "Sky Wizards Academy"
            )
            t.expect(SearchKey.matches(term: "sky wizards", key: key),
                     "the series name is searchable")
            t.expect(SearchKey.matches(term: "traitor", key: key),
                     "and so is the episode's own")
        }

        t.test("punctuation becomes a space, never nothing") {
            // Deleting it would fuse Fate/Zero into "fatezero", which then fails to
            // match the two words anyone would type.
            t.expectEqual(SearchKey.normalize("Fate/Zero"), "fate zero")
            t.expectEqual(SearchKey.normalize("Re:ZERO -Starting Life-"),
                          "re zero starting life")
            t.expectEqual(SearchKey.normalize("K-On!!"), "k on")
        }

        t.test("runs of spaces collapse") {
            t.expectEqual(SearchKey.normalize("  Cowboy   Bebop  "), "cowboy bebop")
        }

        t.test("digits survive, since plenty of titles are numbers") {
            t.expectEqual(SearchKey.normalize("3x3 Eyes"), "3x3 eyes")
            let key = SearchKey.key(name: "5 Centimeters per Second", seriesName: nil)
            t.expect(SearchKey.matches(term: "5 centimeters", key: key))
        }

        t.test("an empty term matches everything, rather than nothing") {
            // Clearing the field must restore the list, not empty it.
            t.expect(SearchKey.matches(term: "", key: "anything"))
            t.expect(SearchKey.matches(term: "   ", key: "anything"))
        }

        t.test("a term of pure punctuation is treated as empty") {
            t.expectEqual(SearchKey.tokens(in: "///").count, 0)
        }
    }
}
