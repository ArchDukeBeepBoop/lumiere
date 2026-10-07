import Foundation
import TestKit
import LumiereKit

/// Recognising creditless openings and endings, and where they sit in a season.
///
/// Several cases below are lifted verbatim from the real library, including every
/// title that contains "nced" without being an ending. Those are the tests that
/// matter: a substring match passes all the NCOP cases and still hides four shows.
@MainActor
func registerCreditlessClassifierTests(_ t: TestRunner) {

    func episode(_ id: String, _ name: String, path: String? = nil) -> LibraryEntry {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": "Episode"]
        if let path { json["Path"] = path }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: Date()), userData: nil
        )
    }

    t.suite("Creditless classifier") { t in

        t.test("NCOP and NCED are recognised, with their kind") {
            t.expectEqual(CreditlessClassifier.kind(name: "Zetman - NCOP"), .opening)
            t.expectEqual(CreditlessClassifier.kind(name: "Zetman - NCED"), .ending)
            t.expectEqual(CreditlessClassifier.kind(name: "Chouja Reideen NCOP2"), .opening)
            t.expectEqual(CreditlessClassifier.kind(name: "Tenchi Muyo! GXP - NCED 02"), .ending)
        }

        t.test("real episode titles containing the letters are not endings") {
            // Every one of these is in the library. A LIKE '%nced%' hides all four.
            for title in [
                "Minced Meat Cutlet / Fried Shrimp",
                "While Visions of Safta Danced in His Head",
                "The Silenced Children",
                "Sentence: Support Retreat from Couveunge Forest",
                "The Night When the Angels Danced (1)",
            ] {
                t.expectNil(CreditlessClassifier.kind(name: title), title)
            }
        }

        t.test("fansub bracket tags do not hide the marker") {
            let name = "[Doki] Zetman - NCOP (1920x1080 Hi10P BD FLAC) [1EFA7FFB]"
            t.expectEqual(CreditlessClassifier.kind(name: name), .opening)
        }

        t.test("underscore-separated names still tokenise") {
            let name = "(Hi10)_Kyoukai_no_Kanata_Idol_Saiban!_-_NCED_(BD_1080p)"
            t.expectEqual(CreditlessClassifier.kind(name: name), .ending)
        }

        t.test("spelled-out forms are recognised too") {
            t.expectEqual(CreditlessClassifier.kind(name: "Creditless Opening 1"), .opening)
            t.expectEqual(CreditlessClassifier.kind(name: "Textless Ending"), .ending)
            t.expect(CreditlessClassifier.isCreditless(name: "Clean Opening"),
                     "a clean opening is creditless")
        }

        t.test("a creditless folder classifies plainly named files inside it") {
            let path = "/Anime/Show/Creditless/OP1.mkv"
            t.expect(CreditlessClassifier.isCreditless(name: "OP1", path: path),
                     "the folder is the signal when the filename is not")
            // And only directories count — a show called Textless keeps its episodes.
            t.expectNil(CreditlessClassifier.kind(name: "Episode 1", path: "/Anime/Textless.mkv"))
        }

        t.test("numbers order several openings of one show") {
            t.expectEqual(CreditlessClassifier.number(in: "Show NCOP2"), 2)
            t.expectEqual(CreditlessClassifier.number(in: "Tenchi Muyo! GXP - NCOP 03"), 3)
            t.expectEqual(CreditlessClassifier.number(in: "Show NCOP"), 0)
        }

        t.test("the opening leads the season and the ending closes it") {
            // The bug, exactly: a null season and episode number collate ahead of
            // episode 1, so this is the order the season query returns.
            let run = [
                episode("nced", "Zetman - NCED"),
                episode("ncop", "Zetman - NCOP"),
                episode("e1", "Untaught Emotions"),
                episode("e2", "In the Fire"),
            ]
            t.expectEqual(CreditlessClassifier.ordered(run, framing: true).map(\.id),
                          ["ncop", "e1", "e2", "nced"])
            // Off, everything creditless goes to the end together.
            t.expectEqual(CreditlessClassifier.ordered(run, framing: false).map(\.id),
                          ["e1", "e2", "ncop", "nced"])
        }

        t.test("several openings and endings keep their own numbering") {
            let run = [
                episode("op1", "GXP - NCOP 01"),
                episode("ed2", "GXP - NCED 02"),
                episode("ed1", "GXP - NCED 01"),
                episode("op2", "GXP - NCOP 02"),
                episode("e1", "Episode One"),
            ]
            t.expectEqual(CreditlessClassifier.ordered(run, framing: true).map(\.id),
                          ["op1", "op2", "e1", "ed1", "ed2"])
            t.expectEqual(CreditlessClassifier.ordered(run, framing: false).map(\.id),
                          ["e1", "op1", "op2", "ed1", "ed2"])
        }

        t.test("a season with none is returned untouched") {
            let entries = [episode("a", "One"), episode("b", "Two")]
            t.expectEqual(CreditlessClassifier.ordered(entries).map(\.id), ["a", "b"])
        }

        t.test("episode order is preserved, never re-sorted") {
            // The caller decides episode order; this only moves the creditless ones.
            let ordered = CreditlessClassifier.ordered([
                episode("e3", "Third"),
                episode("e1", "First"),
                episode("ncop", "NCOP"),
                episode("e2", "Second"),
            ], framing: false)
            t.expectEqual(ordered.map(\.id), ["e3", "e1", "e2", "ncop"])
        }
    }
}
