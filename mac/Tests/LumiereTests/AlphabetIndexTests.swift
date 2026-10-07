import Foundation
import TestKit
import LumiereKit

/// Which letter a title files under, and where each letter starts.
@MainActor
func registerAlphabetIndexTests(_ t: TestRunner) {

    struct Row { let id: String; let sortName: String; let name: String }

    t.suite("Alphabet index") { t in

        t.test("the rail runs # then A to Z") {
            t.expectEqual(AlphabetIndex.letters.count, 27)
            t.expectEqual(AlphabetIndex.letters.first, "#")
            t.expectEqual(AlphabetIndex.letters.last, "Z")
        }

        t.test("the sort key decides the letter, not the display name") {
            // "The Beatles" sorts under B, and a rail that jumped to T for a row
            // sitting under B would be worse than no rail at all.
            t.expectEqual(
                AlphabetIndex.letter(forSortKey: "beatles", fallback: "The Beatles"), "B"
            )
        }

        t.test("digits and non-Latin titles land in the # bucket") {
            // Not a rounding error on an anime library — without this they are
            // unreachable from the rail entirely.
            t.expectEqual(AlphabetIndex.letter(forSortKey: "3x3 Eyes"), "#")
            t.expectEqual(AlphabetIndex.letter(forSortKey: "コードギアス"), "#")
            t.expectEqual(AlphabetIndex.letter(forSortKey: "[Doki] Show"), "#")
        }

        t.test("an empty sort key falls back to the name") {
            t.expectEqual(AlphabetIndex.letter(forSortKey: "", fallback: "Kaiba"), "K")
            t.expectEqual(AlphabetIndex.letter(forSortKey: "", fallback: ""), "#")
        }

        t.test("each letter points at its first row, not its last") {
            let rows = [
                Row(id: "1", sortName: "akira", name: "Akira"),
                Row(id: "2", sortName: "angel beats", name: "Angel Beats"),
                Row(id: "3", sortName: "berserk", name: "Berserk"),
            ]
            let map = AlphabetIndex.firstIds(
                in: rows, id: { $0.id }, sortKey: { $0.sortName }, name: { $0.name }
            )
            t.expectEqual(map["A"], "1")
            t.expectEqual(map["B"], "3")
        }

        t.test("letters with nothing behind them are absent, not empty strings") {
            // The rail dims these rather than hiding them, and nil is how it knows.
            let rows = [Row(id: "1", sortName: "zeta", name: "Zeta")]
            let map = AlphabetIndex.firstIds(
                in: rows, id: { $0.id }, sortKey: { $0.sortName }, name: { $0.name }
            )
            t.expectNil(map["A"])
            t.expectEqual(map["Z"], "1")
        }

        t.test("an empty list produces an empty map, not a crash") {
            let map = AlphabetIndex.firstIds(
                in: [Row](), id: { $0.id }, sortKey: { $0.sortName }, name: { $0.name }
            )
            t.expectEqual(map.count, 0)
        }
    }
}
