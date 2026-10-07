import Foundation
import TestKit
import LumiereKit

/// What a freshly built collection should start with, derived from its members.
@MainActor
func registerCollectionDraftTests(_ t: TestRunner) {

    func entry(
        _ id: String, _ name: String, year: Int? = nil, overview: String? = nil
    ) -> LibraryEntry {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": "Series"]
        if let year { json["ProductionYear"] = year }
        if let overview { json["Overview"] = overview }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: Date()), userData: nil
        )
    }

    t.suite("Collection draft") { t in

        t.test("the year is when the franchise started, not its newest entry") {
            let suggestion = CollectionDraft.suggest(name: "Monogatari", members: [
                entry("2", "Nisemonogatari", year: 2012),
                entry("1", "Bakemonogatari", year: 2009),
                entry("3", "Owarimonogatari", year: 2015),
            ])
            t.expectEqual(suggestion.year, 2009)
        }

        t.test("the synopsis comes from the earliest entry, not the longest") {
            // A sequel's synopsis is usually a recap that assumes the first — which
            // is exactly wrong at the top of a collection.
            let suggestion = CollectionDraft.suggest(name: "Fate", members: [
                entry("late", "Later Entry", year: 2014,
                      overview: "A much longer paragraph that assumes you already "
                              + "know who everyone is and what they did before."),
                entry("first", "First Entry", year: 2006, overview: "Where it begins."),
            ])
            t.expectEqual(suggestion.overview, "Where it begins.")
            t.expectEqual(suggestion.overviewSource, "First Entry")
        }

        t.test("entries with no synopsis are skipped, not preferred") {
            let suggestion = CollectionDraft.suggest(name: "Tenchi", members: [
                entry("blank", "Oldest But Blank", year: 1992),
                entry("good", "Has Words", year: 1995, overview: "Something real."),
            ])
            t.expectEqual(suggestion.overview, "Something real.")
        }

        t.test("a lowercase key is tidied, a real title is left alone") {
            // Keys arrive lowercased from a tag or a filename stem, and a franchise
            // called "monogatari" looks like a bug rather than a decision.
            t.expectEqual(CollectionDraft.displayName("monogatari"), "Monogatari")
            t.expectEqual(CollectionDraft.displayName("holy grail war"), "Holy Grail War")
            t.expectEqual(CollectionDraft.displayName("Fate/stay night"), "Fate/stay night")
        }

        t.test("a collection with no usable members yields blanks, not guesses") {
            let suggestion = CollectionDraft.suggest(name: "Empty", members: [])
            t.expectNil(suggestion.year)
            t.expectEqual(suggestion.overview, "")
            t.expectNil(suggestion.overviewSource)
        }

        t.test("artwork is needed when there is no poster tag") {
            t.expect(CollectionDraft.needsArtwork(nil), "a missing entry needs artwork")
            t.expect(CollectionDraft.needsArtwork(entry("1", "No Poster")),
                     "an entry with no primary tag needs artwork")
        }
    }
}
