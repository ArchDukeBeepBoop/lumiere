import Foundation
import TestKit
import LumiereKit

/// How a specials season is ordered, and — just as importantly — when it is not.
///
/// The rule has to be safe applied to every season list, because that is where it
/// is applied: the episode query does not know whether the season it just read is
/// the specials one, so the ordering detects it and must leave a numbered season
/// exactly as it found it.
@MainActor
func registerSpecialsOrderTests(_ t: TestRunner) {

    let now = Date(timeIntervalSince1970: 1_750_000_000)

    func episode(_ id: String, _ name: String, season: Int?, number: Int?) -> LibraryEntry {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": "Episode",
                                   "SeriesId": "series"]
        if let season { json["ParentIndexNumber"] = season }
        if let number { json["IndexNumber"] = number }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: now), userData: nil
        )
    }

    t.suite("Specials ordering") { t in

        t.test("specials come back by name, not by scraped number") {
            // The numbers here are what a scraper handed back, and they are exactly
            // the order nobody wants to read the list in.
            let specials = [
                episode("c", "Kamogawa Farmers", season: 0, number: 1),
                episode("a", "A Day at the Beach", season: 0, number: 2),
                episode("b", "Barehanded Blade Block", season: 0, number: 3)
            ]
            t.expectEqual(specials.orderedAsSpecials.map(\.id), ["a", "b", "c"])
        }

        t.test("Special 2 comes before Special 10") {
            let specials = [
                episode("s10", "Special 10", season: 0, number: nil),
                episode("s2", "Special 2", season: 0, number: nil)
            ]
            t.expectEqual(specials.orderedAsSpecials.map(\.id), ["s2", "s10"])
        }

        t.test("a numbered season is left exactly as it was") {
            let season = [
                episode("e1", "Zebra", season: 1, number: 1),
                episode("e2", "Apple", season: 1, number: 2)
            ]
            // Alphabetical would put Apple first. A story does not work that way.
            t.expectEqual(season.orderedAsSpecials.map(\.id), ["e1", "e2"])
        }

        t.test("a list mixing specials with real episodes is not reordered") {
            // The all-episodes path can hand over both. Sorting that by name would
            // scatter an OVA through the middle of the run.
            let mixed = [
                episode("e1", "Zebra", season: 1, number: 1),
                episode("sp", "Apple", season: 0, number: 1)
            ]
            t.expectEqual(mixed.orderedAsSpecials.map(\.id), ["e1", "sp"])
        }

        t.test("a season number of null counts as specials, exactly like zero") {
            // The bug the first attempt shipped. Jellyfin writes no season number
            // onto an episode it could not place, so K-ON!'s shorts and five of
            // Tanya's specials carry null — and a test for `== 0` matched none of
            // them, which is why the list came back untouched.
            let specials = [
                episode("s1", "Special 1", season: nil, number: nil),
                episode("s10", "Special 10", season: nil, number: nil),
                episode("s2", "Special 2", season: nil, number: nil)
            ]
            t.expectEqual(specials.orderedAsSpecials.map(\.id), ["s1", "s2", "s10"])
        }

        t.test("null and zero mixed in one specials season still sort together") {
            let specials = [
                episode("b", "Special 10", season: nil, number: nil),
                episode("a", "Special 2", season: 0, number: 3)
            ]
            t.expectEqual(specials.orderedAsSpecials.map(\.id), ["a", "b"])
        }

        t.test("unnumbered shorts inside a real season go to the end, by name") {
            // K-ON! exactly: eight numberless shorts filed under Season 1. They sort
            // on a key of all zeroes, so they sat in front of episode 1 in whatever
            // order the table held them.
            let season = [
                episode("sp10", "Special 10", season: nil, number: nil),
                episode("sp2", "Special 2", season: nil, number: nil),
                episode("e1", "Disband the Club!", season: 1, number: 1),
                episode("e2", "Instruments!", season: 1, number: 2)
            ]
            t.expectEqual(
                season.orderedAsSpecials.map(\.id), ["e1", "e2", "sp2", "sp10"]
            )
        }

        t.test("empty in, empty out") {
            t.expectEqual([LibraryEntry]().orderedAsSpecials.count, 0)
        }
    }
}
