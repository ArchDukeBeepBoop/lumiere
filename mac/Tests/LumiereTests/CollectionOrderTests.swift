import Foundation
import TestKit
import LumiereKit

/// The orders a collection's contents can be read in.
@MainActor
func registerCollectionOrderTests(_ t: TestRunner) {

    func entry(
        _ id: String, _ name: String, year: Int? = nil, seriesId: String? = nil,
        rating: Double? = nil
    ) -> LibraryEntry {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": "Movie"]
        if let year { json["ProductionYear"] = year }
        if let rating { json["CommunityRating"] = rating }
        if let seriesId {
            json["Type"] = "Episode"
            json["SeriesId"] = seriesId
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: Date()), userData: nil
        )
    }

    t.suite("Collection order") { t in

        t.test("the collection's own order is left alone by default") {
            let items = [entry("c", "C"), entry("a", "A"), entry("b", "B")]
            t.expectEqual(
                CollectionOrder.sorted(items, by: .manual).map(\.id), ["c", "a", "b"]
            )
        }

        t.test("name order is human, not ASCII") {
            let items = [entry("2", "Item 10"), entry("1", "Item 2")]
            t.expectEqual(
                CollectionOrder.sorted(items, by: .name).map(\.id), ["1", "2"]
            )
        }

        t.test("year order runs oldest first") {
            let items = [entry("new", "New", year: 2016), entry("old", "Old", year: 1998)]
            t.expectEqual(
                CollectionOrder.sorted(items, by: .releaseDate).map(\.id), ["old", "new"]
            )
        }

        t.test("an undated title sorts last, not to 1970") {
            // A missing year is unknown, not ancient. Sorting it first would bury
            // everything real behind the entries nobody scraped properly.
            let items = [entry("none", "Unknown"), entry("dated", "Dated", year: 2001)]
            t.expectEqual(
                CollectionOrder.sorted(items, by: .releaseDate).map(\.id), ["dated", "none"]
            )
        }

        t.test("watch order keeps a series together and runs franchises oldest first") {
            // A film from 2011 must not land between two episodes of a 2006 series.
            let items = [
                entry("film", "A Later Film", year: 2011),
                entry("s1e1", "Episode 1", year: 2006, seriesId: "S"),
                entry("s1e2", "Episode 2", year: 2008, seriesId: "S"),
            ]
            t.expectEqual(
                CollectionOrder.sorted(items, by: .watchOrder).map(\.id),
                ["s1e1", "s1e2", "film"]
            )
        }

        t.test("a series anchors on its earliest entry, not its first listed") {
            let items = [
                entry("old", "Standalone", year: 1999),
                entry("s2", "Second Part", year: 2005, seriesId: "S"),
                entry("s1", "First Part", year: 1995, seriesId: "S"),
            ]
            // The series anchors at 1995, so it precedes the 1999 film entirely.
            t.expectEqual(
                CollectionOrder.sorted(items, by: .watchOrder).map(\.id),
                ["s1", "s2", "old"]
            )
        }

        t.test("rating order puts unrated last") {
            let items = [entry("none", "Unrated"), entry("good", "Good", rating: 8.4)]
            t.expectEqual(
                CollectionOrder.sorted(items, by: .rating).map(\.id).last, "none"
            )
        }

        t.test("an empty collection sorts to nothing in every order") {
            for order in CollectionOrder.allCases {
                t.expectEqual(CollectionOrder.sorted([], by: order).count, 0)
            }
        }
    }
}
