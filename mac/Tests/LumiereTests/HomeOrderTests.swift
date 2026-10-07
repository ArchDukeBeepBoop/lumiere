import Foundation
import TestKit
import LumiereKit

/// The rules for reconciling a stored home-screen order with the libraries that
/// exist now. Every case here is a way the two can disagree in normal use.
@MainActor
func registerHomeOrderTests(_ t: TestRunner) async {

    t.suite("Home screen order") { t in

        let libraries = ["lib-movies", "lib-anime", "lib-tv"]

        t.test("an untouched install gets the order the app has always drawn") {
            let order = HomeOrder.defaultOrder(libraryIds: libraries)
            t.expectEqual(order.first, .spotlight)
            t.expectEqual(order.last, .latest(libraryId: "lib-tv"))
            t.expectEqual(order.count, 14 + libraries.count)
        }

        t.test("an order an earlier version saved untouched follows the new default") {
            let old = "spotlight,quickLinks,libraries,continueWatching,genres,nextUp,recentlyAdded,"
                + "topFilms,topSeries,topAnime,latest:lib-movies,latest:lib-anime,latest:lib-tv"
            t.expectEqual(HomeOrder.resolve(stored: old, libraryIds: libraries),
                          HomeOrder.defaultOrder(libraryIds: libraries))
            t.expectEqual(HomeOrder.defaultOrder(libraryIds: libraries)[1], .continueWatching)
        }

        t.test("no stored order falls back to the default") {
            t.expectEqual(
                HomeOrder.resolve(stored: nil, libraryIds: libraries),
                HomeOrder.defaultOrder(libraryIds: libraries)
            )
            t.expectEqual(
                HomeOrder.resolve(stored: "", libraryIds: libraries),
                HomeOrder.defaultOrder(libraryIds: libraries)
            )
        }

        t.test("a stored order is honoured, including moved Latest rows") {
            let wanted: [HomeSection] = [
                .latest(libraryId: "lib-anime"), .continueWatching, .spotlight,
                .quickLinks, .libraries, .finishSeason, .genres, .nextUp,
                .forgotten, .continueSeries, .becauseYouWatched, .recentlyAdded, .topFilms, .topSeries, .topAnime,
                .latest(libraryId: "lib-movies"), .latest(libraryId: "lib-tv"),
            ]
            let resolved = HomeOrder.resolve(
                stored: HomeOrder.encode(wanted), libraryIds: libraries
            )
            t.expectEqual(resolved, wanted)
        }

        t.test("a removed library's row is dropped rather than leaving a gap") {
            let stored = HomeOrder.encode(
                HomeOrder.defaultOrder(libraryIds: libraries + ["lib-gone"])
            )
            let resolved = HomeOrder.resolve(stored: stored, libraryIds: libraries)
            t.expect(!resolved.contains(.latest(libraryId: "lib-gone")))
            t.expectEqual(resolved.count, 14 + libraries.count)
        }

        t.test("a new library lands with the other Latest rows, not at the end") {
            // The order someone actually made: Continue Watching first, Top 10
            // Films last. A library added afterwards must not jump the queue and
            // must not land under the row they deliberately buried.
            var custom: [HomeSection] = [.continueWatching, .spotlight, .quickLinks,
                                         .libraries, .finishSeason, .genres, .nextUp,
                                         .forgotten, .continueSeries, .becauseYouWatched, .recentlyAdded,
                                         .topSeries, .topAnime,
                                         .latest(libraryId: "lib-movies"),
                                         .latest(libraryId: "lib-tv"),
                                         .topFilms]
            let resolved = HomeOrder.resolve(
                stored: HomeOrder.encode(custom),
                libraryIds: ["lib-movies", "lib-anime", "lib-tv"]
            )
            custom.insert(.latest(libraryId: "lib-anime"), at: 14)
            t.expectEqual(resolved, custom)
        }

        t.test("a section the stored order never knew about is restored in place") {
            // What a future version's new row does to an order written today: the
            // stored list simply does not mention it.
            let withoutGenres = HomeOrder.defaultOrder(libraryIds: libraries)
                .filter { $0 != .genres }
            let resolved = HomeOrder.resolve(
                stored: HomeOrder.encode(withoutGenres), libraryIds: libraries
            )
            t.expectEqual(resolved, HomeOrder.defaultOrder(libraryIds: libraries))
        }

        t.test("a duplicated section is drawn once") {
            let resolved = HomeOrder.resolve(
                stored: "spotlight,spotlight,continueWatching", libraryIds: libraries
            )
            t.expectEqual(resolved.filter { $0 == .spotlight }.count, 1)
        }

        t.test("an unrecognised id is ignored rather than failing the whole order") {
            let resolved = HomeOrder.resolve(
                stored: "spotlight,nonsense,latest:,continueWatching",
                libraryIds: libraries
            )
            t.expectEqual(resolved.count, 14 + libraries.count)
            t.expectEqual(resolved.first, .spotlight)
        }

        t.test("moving stops at the ends instead of wrapping") {
            let order = HomeOrder.defaultOrder(libraryIds: libraries)
            t.expectEqual(HomeOrder.moved(.spotlight, by: -1, in: order), order)
            t.expectEqual(
                HomeOrder.moved(.latest(libraryId: "lib-tv"), by: 1, in: order), order
            )
        }

        t.test("moving swaps with the neighbour in that direction") {
            let order = HomeOrder.defaultOrder(libraryIds: libraries)
            let moved = HomeOrder.moved(.continueWatching, by: -1, in: order)
            t.expectEqual(moved.first, .continueWatching)
            t.expectEqual(moved[1], .spotlight)
            t.expectEqual(moved.count, order.count)
        }

        t.test("an id survives a round trip, libraries included") {
            for section in HomeOrder.defaultOrder(libraryIds: libraries) {
                t.expectEqual(HomeSection(id: section.id), section)
            }
        }
    }
}

/// The library list follows the shelf order.
@MainActor
func registerLibraryOrderTests(_ t: TestRunner) {

    t.suite("Library order follows the home order") { t in

        t.test("an untouched install keeps the server's order") {
            t.expectEqual(
                HomeOrder.libraryOrder(stored: nil, libraryIds: ["a", "b", "c"]),
                ["a", "b", "c"]
            )
        }

        t.test("moving a Latest row moves the library with it") {
            // The order as written by the settings pane: c's row ahead of a's.
            let moved = HomeOrder.encode([
                .spotlight, .libraries,
                .latest(libraryId: "c"), .latest(libraryId: "a"), .latest(libraryId: "b"),
            ])
            t.expectEqual(
                HomeOrder.libraryOrder(stored: moved, libraryIds: ["a", "b", "c"]),
                ["c", "a", "b"]
            )
        }

        t.test("a library the stored order never mentioned still lands sensibly") {
            // `resolve` reinserts a new library beside the other Latest rows, so
            // it is ranked rather than swept to the end.
            let stored = HomeOrder.encode([
                .latest(libraryId: "b"), .latest(libraryId: "a"),
            ])
            let order = HomeOrder.libraryOrder(stored: stored, libraryIds: ["a", "b", "new"])
            t.expectEqual(order.count, 3)
            t.expect(order.firstIndex(of: "b")! < order.firstIndex(of: "a")!)
        }

        t.test("the order is stable, not merely correct") {
            // Two runs of the same input must agree: an unstable sort would let
            // unranked libraries swap places between launches.
            let ids = ["a", "b", "c", "d", "e"]
            let first = HomeOrder.libraryOrder(stored: "", libraryIds: ids)
            let second = HomeOrder.libraryOrder(stored: "", libraryIds: ids)
            t.expectEqual(first, second)
            t.expectEqual(first, ids)
        }
    }
}

/// TMDB's season payload, as the still fetcher reads it.
@MainActor
func registerEpisodeStillTests(_ t: TestRunner) {

    t.suite("TMDB episode stills") { t in

        t.test("an episode with no picture is dropped rather than sent as a broken URL") {
            let json = Data("""
            {"episodes": [
              {"episode_number": 1, "season_number": 1, "still_path": "/abc.jpg"},
              {"episode_number": 2, "season_number": 1, "still_path": null},
              {"episode_number": 3, "season_number": 1, "still_path": ""}
            ]}
            """.utf8)

            let stills = try EpisodeStillFetch.decode(json, seasonNumber: 1)
            t.expectEqual(stills.count, 1)
            t.expectEqual(stills.first?.episode, 1)
        }

        t.test("the URL is built on TMDB's image host at a drawn size") {
            let json = Data("""
            {"episodes": [{"episode_number": 4, "still_path": "/x.jpg"}]}
            """.utf8)
            let stills = try EpisodeStillFetch.decode(json, seasonNumber: 2)
            // The host has to be one the server's allowlist accepts, or every
            // fetch is refused on arrival.
            t.expectEqual(
                stills.first?.imageURL,
                "https://image.tmdb.org/t/p/\(EpisodeStillFetch.stillSize)/x.jpg"
            )
            // The season we asked for stands in when the payload omits it.
            t.expectEqual(stills.first?.season, 2)
        }

        t.test("a response that is not an episode list fails rather than naming nothing") {
            t.expectThrows {
                _ = try EpisodeStillFetch.decode(Data("not json".utf8), seasonNumber: 1)
            }
        }
    }
}

/// What counts as finished for Continue Watching.
@MainActor
func registerResumeCutoffTests(_ t: TestRunner) {

    /// One episode, with a runtime in ticks and a position in ticks.
    func entry(runtimeSeconds: Double?, positionSeconds: Double, played: Bool) throws
        -> LibraryEntry
    {
        var object: [String: Any] = ["Id": "1", "Name": "x", "Type": "Episode"]
        if let runtimeSeconds {
            object["RunTimeTicks"] = Int(runtimeSeconds * 10_000_000)
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        let record = ItemRecord(from: item, serverId: "s1", syncedAt: Date())
        var userData = UserDataRecord(itemId: "1", from: nil, updatedAt: Date())
        userData.played = played
        userData.playbackPositionTicks = Int64(positionSeconds * 10_000_000)
        return LibraryEntry(item: record, userData: userData)
    }

    t.suite("Continue Watching cutoff") { t in

        t.test("an episode stopped on the last frame is finished") {
            // The case this exists for: the player reports the final position and
            // nothing marks the row watched, so it read as 99.99% for ever.
            let almostDone = try entry(
                runtimeSeconds: 1440, positionSeconds: 1439.9, played: false
            )
            t.expect(almostDone.isFinishedForResume, "99.99% is finished")
        }

        t.test("halfway through is not finished") {
            let half = try entry(runtimeSeconds: 1440, positionSeconds: 720, played: false)
            t.expect(!half.isFinishedForResume, "50% is what the shelf is for")
        }

        t.test("just under the cut stays") {
            // 89%: a long film's last stretch is still worth finishing.
            let nearly = try entry(runtimeSeconds: 1000, positionSeconds: 890, played: false)
            t.expect(!nearly.isFinishedForResume, "89% should stay on the shelf")
            let over = try entry(runtimeSeconds: 1000, positionSeconds: 900, played: false)
            t.expect(over.isFinishedForResume, "90% is the cut")
        }

        t.test("an unknown runtime is never finished by percentage") {
            // It cannot be a percentage of anything, and dropping what cannot be
            // measured loses rows silently.
            let unknown = try entry(runtimeSeconds: nil, positionSeconds: 5000, played: false)
            t.expect(!unknown.isFinishedForResume, "no runtime, no cutoff")
        }

        t.test("the played flag still decides on its own") {
            let played = try entry(runtimeSeconds: 1440, positionSeconds: 10, played: true)
            t.expect(played.isFinishedForResume, "watched is watched")
        }
    }
}
