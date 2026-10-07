import Foundation
import TestKit
import LumiereKit

/// How a run of newly added episodes becomes one tile — and which tile it becomes.
@MainActor
func registerLatestShelfTests(_ t: TestRunner) {

    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let iso = ISO8601DateFormatter()

    func episode(
        id: String,
        seriesId: String?,
        premiere: Date?
    ) -> LibraryEntry {
        var json: [String: Any] = ["Id": id, "Name": "Episode \(id)", "Type": "Episode"]
        if let seriesId {
            json["SeriesId"] = seriesId
            json["SeriesName"] = "Show \(seriesId)"
        }
        if let premiere { json["PremiereDate"] = iso.string(from: premiere) }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: now), userData: nil
        )
    }

    func movie(id: String) -> LibraryEntry {
        let json: [String: Any] = ["Id": id, "Name": "Film \(id)", "Type": "Movie"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: now), userData: nil
        )
    }

    func series(id: String) -> LibraryEntry {
        let json: [String: Any] = ["Id": id, "Name": "Show \(id)", "Type": "Series"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: now), userData: nil
        )
    }

    /// Days before `now`.
    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 24 * 60 * 60) }

    t.suite("Latest shelf collapsing") { t in

        t.test("a season drop becomes one tile, not twenty-six") {
            let entries = (1...26).map {
                episode(id: "e\($0)", seriesId: "S", premiere: daysAgo(2000))
            }
            let slots = LatestShelf.collapse(entries, now: now)
            t.expectEqual(slots.count, 1)
            t.expectEqual(slots[0].episodeCount, 26)
        }

        t.test("an old import collapses to the series") {
            let slots = LatestShelf.collapse([
                episode(id: "e1", seriesId: "S", premiere: daysAgo(900)),
                episode(id: "e2", seriesId: "S", premiere: daysAgo(907)),
            ], now: now)
            t.expectEqual(slots[0].seriesId, "S")
        }

        t.test("this week's episode keeps its own tile") {
            let slots = LatestShelf.collapse([
                episode(id: "e9", seriesId: "S", premiere: daysAgo(3)),
                episode(id: "e8", seriesId: "S", premiere: daysAgo(10)),
            ], now: now)
            t.expectEqual(slots.count, 1)
            t.expectNil(slots[0].seriesId)
            // The newest of the run, since shelves arrive newest-first.
            t.expectEqual(slots[0].representative.id, "e9")
            t.expectEqual(slots[0].episodeCount, 2)
        }

        t.test("the recency window is read from the newest episode only") {
            // An old back catalogue behind a current episode is still a current show.
            let entries = [episode(id: "new", seriesId: "S", premiere: daysAgo(1))]
                + (1...12).map { episode(id: "old\($0)", seriesId: "S", premiere: daysAgo(3000)) }
            let slots = LatestShelf.collapse(entries, now: now)
            t.expectNil(slots[0].seriesId)
            t.expectEqual(slots[0].episodeCount, 13)
        }

        t.test("the boundary sits at the release window") {
            let inside = LatestShelf.collapse(
                [episode(id: "a", seriesId: "S", premiere: daysAgo(20))], now: now
            )
            t.expectNil(inside[0].seriesId)

            let outside = LatestShelf.collapse(
                [episode(id: "b", seriesId: "S", premiere: daysAgo(22))], now: now
            )
            t.expectEqual(outside[0].seriesId, "S")
        }

        t.test("an undated episode falls back to the series tile") {
            let slots = LatestShelf.collapse(
                [episode(id: "a", seriesId: "S", premiere: nil)], now: now
            )
            t.expectEqual(slots[0].seriesId, "S")
        }

        t.test("different shows keep their own tiles, in arrival order") {
            let slots = LatestShelf.collapse([
                episode(id: "a1", seriesId: "A", premiere: daysAgo(400)),
                episode(id: "b1", seriesId: "B", premiere: daysAgo(400)),
                episode(id: "a2", seriesId: "A", premiere: daysAgo(407)),
                episode(id: "c1", seriesId: "C", premiere: daysAgo(400)),
            ], now: now)
            t.expectEqual(slots.count, 3)
            t.expectEqual(slots.map { $0.seriesId ?? "" }, ["A", "B", "C"])
            t.expectEqual(slots[0].episodeCount, 2)
        }

        t.test("films and series pass through untouched") {
            let slots = LatestShelf.collapse([movie(id: "m1"), movie(id: "m2")], now: now)
            t.expectEqual(slots.count, 2)
            t.expectNil(slots[0].seriesId)
            t.expectEqual(slots[1].representative.id, "m2")
        }

        t.test("an episode with no series is never dropped") {
            // Grouping it is impossible, and silently losing content would be worse
            // than one extra tile.
            let slots = LatestShelf.collapse([
                episode(id: "loose1", seriesId: nil, premiere: daysAgo(900)),
                episode(id: "loose2", seriesId: nil, premiere: daysAgo(900)),
            ], now: now)
            t.expectEqual(slots.count, 2)
        }

        t.test("an empty shelf stays empty") {
            t.expectEqual(LatestShelf.collapse([], now: now).count, 0)
        }
        t.test("a series and its own new episodes are one tile, not two") {
            // The reported bug: a show whose series row *and* whose episodes both
            // landed in the window appeared twice on the shelf, taking the place
            // of something else in the library.
            let slots = LatestShelf.collapse([
                series(id: "show"),
                episode(id: "e2", seriesId: "show", premiere: daysAgo(400)),
                episode(id: "e1", seriesId: "show", premiere: daysAgo(400)),
            ], now: now)
            t.expectEqual(slots.count, 1)
            t.expectEqual(slots.first?.representative.id, "show")
        }

        t.test("the same series row twice still yields one tile") {
            let slots = LatestShelf.collapse([
                series(id: "show"), series(id: "show"),
            ], now: now)
            t.expectEqual(slots.count, 1)
        }

        t.test("episodes first, then the series row, is still one tile") {
            // Order depends on which row the server dated later, so both ways round
            // have to collapse.
            let slots = LatestShelf.collapse([
                episode(id: "e1", seriesId: "show", premiere: daysAgo(400)),
                series(id: "show"),
            ], now: now)
            t.expectEqual(slots.count, 1)
        }

        t.test("two different shows still get a tile each") {
            let slots = LatestShelf.collapse([
                series(id: "a"),
                episode(id: "b1", seriesId: "b", premiere: daysAgo(400)),
            ], now: now)
            t.expectEqual(slots.count, 2)
        }

    }

    t.suite("Filling a Latest shelf") { t in

        // The measured failure: one fixed query gave TV Shows 6 tiles of a wanted
        // 20 and Anime 7, while every other shelf on screen had twenty — so the two
        // libraries with the most in them looked the emptiest.
        t.test("keeps asking while the shelf is short and rows remain") {
            t.expect(
                LatestShelf.needsMoreRows(filled: 6, fetched: 60, asked: 60, target: 20),
                "a short shelf with a full page behind it must read deeper"
            )
        }

        t.test("stops the moment the shelf is full") {
            t.expect(
                !LatestShelf.needsMoreRows(filled: 20, fetched: 60, asked: 60, target: 20),
                "a full shelf must not cost another query"
            )
            t.expect(
                !LatestShelf.needsMoreRows(filled: 53, fetched: 60, asked: 60, target: 20),
                "nor must an over-full one"
            )
        }

        // Hobby TV: thirteen shows in eighty rows. Without this the home screen
        // would read that library to the end on every load to learn the same answer.
        t.test("stops when the library runs out, however short the shelf") {
            t.expect(
                !LatestShelf.needsMoreRows(filled: 13, fetched: 80, asked: 240, target: 20),
                "a short page means the library is exhausted"
            )
        }

        t.test("an empty library asks nothing further") {
            t.expect(!LatestShelf.needsMoreRows(filled: 0, fetched: 0, asked: 60, target: 20))
        }

        // The ladder has to be increasing and finite, or the loop either re-reads
        // the same rows forever or never terminates.
        // The substitution step is what made row-level hiding insufficient: an
        // episode still carries its series id, so a dismissed show was rebuilt from
        // its episodes and fetched back by id.
        t.test("a dismissed series leaves no slot pointing back at it") {
            let hidden: Set<String> = ["show-1"]
            let slots = LatestShelf.collapse([
                episode(id: "e1", seriesId: "show-1", premiere: nil),
                episode(id: "e2", seriesId: "show-2", premiere: nil),
            ]).filter { slot in
                guard let seriesId = slot.seriesId else { return true }
                return !hidden.contains(seriesId)
            }
            t.expectEqual(slots.compactMap(\.seriesId), ["show-2"])
        }

        t.test("the ladder climbs and ends") {
            t.expect(LatestShelf.fillSteps.count >= 2, "one step is not a ladder")
            t.expectEqual(LatestShelf.fillSteps, LatestShelf.fillSteps.sorted())
            t.expectEqual(Set(LatestShelf.fillSteps).count, LatestShelf.fillSteps.count)
            t.expect(LatestShelf.fillSteps.allSatisfy { $0 > 0 }, "no empty request")
        }

        // Ties are the reason this escalates a limit instead of paging by offset:
        // hundreds of rows here share a contentDate to the second, and SQLite gives
        // no stable order among them, so offset paging can repeat one row and skip
        // another. Pinned as a property of the ladder: every step re-reads from the
        // top, so step N is a superset of step N-1.
        t.test("each step is a superset of the last, so nothing is skipped") {
            for (a, b) in zip(LatestShelf.fillSteps, LatestShelf.fillSteps.dropFirst()) {
                t.expect(b > a, "step \(b) must extend step \(a), not offset past it")
            }
        }
    }
}
