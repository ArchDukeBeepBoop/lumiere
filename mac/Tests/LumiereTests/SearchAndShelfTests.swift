import Foundation
import TestKit
import LumiereKit

/// What order search results come back in.
@MainActor
func registerSearchRankingTests(_ t: TestRunner) {

    t.suite("Search ranking") { t in

        t.test("an exact title beats everything that merely contains the word") {
            let exact = SearchRanking.score(name: "Gundam", term: "gundam")
            let long = SearchRanking.score(
                name: "Mobile Suit Gundam: Iron-Blooded Orphans", term: "gundam"
            )
            t.expect(exact > long, "\(exact) should beat \(long)")
        }

        t.test("a title that starts with the term beats one that buries it") {
            let prefix = SearchRanking.score(name: "Sky Wizards Academy", term: "sky")
            let buried = SearchRanking.score(name: "Under the Sky", term: "sky")
            t.expect(prefix > buried, "\(prefix) should beat \(buried)")
        }

        t.test("the shorter of two equals comes first") {
            let short = SearchRanking.score(name: "Gundam Wing", term: "gundam")
            let long = SearchRanking.score(
                name: "Gundam Build Fighters Try Island Wars", term: "gundam"
            )
            t.expect(short > long, "\(short) should beat \(long)")
        }

        t.test("kind is only ever a tie-break, never a band") {
            // An episode named exactly must still beat a series that only
            // contains the word, whatever the kind weights say.
            let episode = SearchRanking.score(name: "Jet Alone", term: "jet alone", kindWeight: 1)
            let series = SearchRanking.score(
                name: "Jet Alone and the Long Afternoon", term: "jet alone", kindWeight: 3
            )
            t.expect(episode > series, "\(episode) should beat \(series)")
        }

        t.test("a term that matches nothing in the title scores lowest, not zero") {
            // Matched through a series name or a romaji alternative: still a
            // result, still last.
            t.expectEqual(SearchRanking.band(name: "Some Episode", term: "gundam"),
                          .matchedElsewhere)
        }

        t.test("an empty term ranks nothing") {
            t.expectEqual(SearchRanking.band(name: "Gundam", term: ""), .none)
            t.expectEqual(SearchRanking.score(name: "Gundam", term: ""), 0)
        }
    }
}

/// The seven-shelf cap.
@MainActor
func registerHomeShelfCapTests(_ t: TestRunner) {

    t.suite("Home shelf cap") { t in

        t.test("a screen inside the limit is left alone") {
            let rows = Array(1...5)
            let out = HomeShelfCap.apply(to: rows, isEmpty: { _ in false })
            t.expectEqual(out.visible.count, 5)
            t.expectEqual(out.heldBack.count, 0)
        }

        t.test("everything past seven is held back, not dropped") {
            let rows = Array(1...17)
            let out = HomeShelfCap.apply(to: rows, isEmpty: { _ in false })
            t.expectEqual(out.visible.count, 7)
            t.expectEqual(out.heldBack.count, 10)
        }

        t.test("an empty shelf does not spend one of the seven places") {
            // Ten rows, three of them empty: seven full ones should still show.
            let rows = Array(1...10)
            let out = HomeShelfCap.apply(to: rows, isEmpty: { [1, 2, 3].contains($0) })
            t.expectEqual(out.visible.count, 7)
            t.expectEqual(out.visible.first, 4)
            // And the empty ones appear in neither list.
            t.expectEqual(out.heldBack.count, 0)
        }

        t.test("showing all lifts the cap without reordering anything") {
            let rows = Array(1...17)
            let out = HomeShelfCap.apply(to: rows, isEmpty: { _ in false }, showAll: true)
            t.expectEqual(out.visible, rows)
            t.expectEqual(out.heldBack.count, 0)
        }

        t.test("furniture is not a shelf and is never counted") {
            t.expectEqual(HomeSection.spotlight.isShelf, false)
            t.expectEqual(HomeSection.quickLinks.isShelf, false)
            t.expectEqual(HomeSection.libraries.isShelf, false)
            t.expectEqual(HomeSection.continueWatching.isShelf, true)
            t.expectEqual(HomeSection.latest(libraryId: "x").isShelf, true)
        }
    }
}

/// The one thing a detail page says first.
@MainActor
func registerDominantFactTests(_ t: TestRunner) {

    func episode(_ index: Int, played: Bool) throws -> LibraryEntry {
        let object: [String: Any] = [
            "Id": "e\(index)", "Name": "Episode \(index)", "Type": "Episode",
            "IndexNumber": index,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        let record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
        var userData = UserDataRecord(itemId: "e\(index)", from: nil, updatedAt: Date())
        userData.played = played
        return LibraryEntry(item: record, userData: userData)
    }

    func season(watchedThrough: Int, of total: Int) throws -> [LibraryEntry] {
        try (1...total).map { try episode($0, played: $0 <= watchedThrough) }
    }

    t.suite("Dominant fact") { t in

        t.test("a part-watched season says where you are") {
            t.expectEqual(
                DominantFact.seasonProgress(episodes: try season(watchedThrough: 6, of: 24)),
                "You are on episode 7 of 24"
            )
        }

        t.test("a season never started says nothing") {
            t.expectNil(
                DominantFact.seasonProgress(episodes: try season(watchedThrough: 0, of: 12))
            )
        }

        t.test("a finished season says nothing") {
            t.expectNil(
                DominantFact.seasonProgress(episodes: try season(watchedThrough: 12, of: 12))
            )
        }

        t.test("watched out of order points at the first gap, not the count") {
            // Episodes 1, 2 and 5 seen: you are on 3, not on 4.
            var episodes = try season(watchedThrough: 2, of: 6)
            episodes[4] = try episode(5, played: true)
            t.expectEqual(
                DominantFact.seasonProgress(episodes: episodes),
                "You are on episode 3 of 6"
            )
        }

        t.test("a part-watched film says how long is left") {
            t.expectEqual(
                DominantFact.filmRemaining(runtimeSeconds: 7020, resumeSeconds: 4800),
                "37 minutes left"
            )
            t.expectEqual(
                DominantFact.filmRemaining(runtimeSeconds: 12000, resumeSeconds: 600),
                "3 hr 10 min left"
            )
        }

        t.test("a film barely started, or nearly over, says nothing") {
            t.expectNil(DominantFact.filmRemaining(runtimeSeconds: 7020, resumeSeconds: 10))
            t.expectNil(DominantFact.filmRemaining(runtimeSeconds: 7020, resumeSeconds: 6990))
            t.expectNil(DominantFact.filmRemaining(runtimeSeconds: nil, resumeSeconds: 600))
        }
    }
}

/// Which server segments are worth acting on.
@MainActor
func registerMediaSegmentTests(_ t: TestRunner) {

    func segment(type: String, start: Int64?, end: Int64?) throws -> MediaSegment {
        var object: [String: Any] = ["Id": "s", "Type": type]
        if let start { object["StartTicks"] = start }
        if let end { object["EndTicks"] = end }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JellyfinClient.decoder.decode(MediaSegment.self, from: data)
    }

    let minute: Int64 = 600_000_000

    t.suite("Media segments") { t in

        t.test("credits with no start are not credits from frame zero") {
            // The bug: StartTicks absent read as zero, so Skip Credits was
            // offered over the opening titles.
            let outro = try segment(type: "Outro", start: nil, end: 24 * minute)
            t.expectEqual(outro.isWellFormed, false)
        }

        t.test("credits that claim to start at zero are rejected too") {
            let outro = try segment(type: "Credits", start: 0, end: 24 * minute)
            t.expectEqual(outro.isWellFormed, false)
        }

        t.test("real credits are kept") {
            let outro = try segment(type: "Outro", start: 22 * minute, end: 24 * minute)
            t.expectEqual(outro.isWellFormed, true)
            t.expectEqual(outro.skipLabel, "Skip Credits")
        }

        t.test("an intro may legitimately start at the first frame") {
            let intro = try segment(type: "Intro", start: 0, end: 90 * 10_000_000)
            t.expectEqual(intro.isWellFormed, true)
        }

        t.test("a segment with no end is not a stretch of anything") {
            t.expectEqual(try segment(type: "Intro", start: 0, end: nil).isWellFormed, false)
        }

        t.test("a segment that ends before it starts is rejected") {
            let backwards = try segment(type: "Intro", start: 5 * minute, end: minute)
            t.expectEqual(backwards.isWellFormed, false)
        }
    }
}

/// Which libraries feed Recently Added.
@MainActor
func registerRecentlyAddedPolicyTests(_ t: TestRunner) {

    func library(_ id: String, _ name: String, type: String?) throws -> LibraryRecord {
        var object: [String: Any] = ["Id": id, "Name": name, "Type": "CollectionFolder"]
        if let type { object["CollectionType"] = type }
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryRecord(from: item, serverId: "s", sortIndex: 0)
    }

    t.suite("Recently Added policy") { t in

        t.test("folder, private and adult libraries are out by default") {
            let libs = [
                try library("a", "Anime", type: "tvshows"),
                try library("b", "3D", type: nil),
                try library("c", "Adult", type: "tvshows"),
                try library("d", "TV Shows", type: "tvshows"),
            ]
            let out = RecentlyAddedPolicy.excluded(libraries: libs, privateIds: ["d"], stored: nil)
            t.expectEqual(out, ["b", "c", "d"])
        }

        t.test("a stored choice wins over the default either way") {
            let libs = [
                try library("c", "Adult", type: "tvshows"),
                try library("a", "Anime", type: "tvshows"),
            ]
            let stored = RecentlyAddedPolicy.store(["c": true, "a": false])
            let out = RecentlyAddedPolicy.excluded(libraries: libs, privateIds: [], stored: stored)
            t.expectEqual(out, ["a"])
        }

        t.test("choices survive a round trip") {
            let choices = ["x": true, "y": false]
            t.expectEqual(RecentlyAddedPolicy.choices(from: RecentlyAddedPolicy.store(choices)), choices)
        }
    }
}
