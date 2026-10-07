import Foundation
import TestKit
import LumiereKit

/// How the hero's rotation is assembled from per-library candidates.
///
/// The query that produces those candidates needs a database and is not covered
/// here; the mixing rule is the part with a decision in it, and it is pure.
@MainActor
func registerSpotlightMixTests(_ t: TestRunner) {

    let now = Date(timeIntervalSince1970: 1_750_000_000)

    func title(_ id: String, rating: Double) -> LibraryEntry {
        let json: [String: Any] = [
            "Id": id, "Name": "Title \(id)", "Type": "Movie", "CommunityRating": rating
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: now), userData: nil
        )
    }

    t.suite("Spotlight mixing") { t in

        t.test("takes one from each library before taking a second from any") {
            let anime = [title("a1", rating: 9.5), title("a2", rating: 9.4)]
            let films = [title("f1", rating: 7.0), title("f2", rating: 6.9)]
            let shows = [title("t1", rating: 8.0)]

            let mixed = Spotlight.mix([anime, films, shows], limit: 6)
            t.expectEqual(mixed.map(\.id), ["a1", "f1", "t1", "a2", "f2"])
        }

        t.test("a library with one eligible title still gets a slot") {
            // The case a global sort by rating loses: anime out-rates everything
            // here, so a flat top-four would be four anime and no films at all.
            let anime = (1...10).map { title("a\($0)", rating: 9.0) }
            let films = [title("f1", rating: 6.0)]

            let mixed = Spotlight.mix([anime, films], limit: 4)
            t.expect(mixed.map(\.id).contains("f1"), "the one film must appear")
            t.expectEqual(mixed[0].id, "a1")
        }

        t.test("the same title in two libraries appears once") {
            let films = [title("shared", rating: 8.5), title("f2", rating: 8.0)]
            let animeFilms = [title("shared", rating: 8.5), title("x2", rating: 7.5)]

            let mixed = Spotlight.mix([films, animeFilms], limit: 6)
            // The duplicate is skipped rather than deferred: the second library's
            // turn at rank 0 is spent, and it contributes again at rank 1.
            t.expectEqual(mixed.map(\.id), ["shared", "f2", "x2"])
        }

        t.test("stops at the limit") {
            let group = (1...20).map { title("g\($0)", rating: 8.0) }
            t.expectEqual(Spotlight.mix([group], limit: 3).count, 3)
        }

        t.test("a different offset features a different slice of the same pool") {
            let pool = (1...10).map { title("p\($0)", rating: 9.0) }

            let today = Spotlight.mix([pool], limit: 3, day: 100)
            let tomorrow = Spotlight.mix([pool], limit: 3, day: 101)

            t.expectEqual(today.map(\.id), ["p1", "p2", "p3"])
            t.expectEqual(tomorrow.map(\.id), ["p2", "p3", "p4"])
        }

        t.test("the same session always gives the same hero") {
            // The property that matters more than the change itself: a refresh or a
            // sync must not reshuffle what is on screen mid-session.
            let pool = (1...10).map { title("p\($0)", rating: 9.0) }
            t.expectEqual(
                Spotlight.mix([pool], limit: 4, day: 7).map(\.id),
                Spotlight.mix([pool], limit: 4, day: 7).map(\.id)
            )
        }

        t.test("rotation wraps rather than running off a short library") {
            // The reason each library is rotated by its own size: one film and a day
            // number in the thousands must still yield that film, not an empty slot.
            let films = [title("only", rating: 6.0)]
            t.expectEqual(Spotlight.mix([films], limit: 3, day: 4_321).map(\.id), ["only"])
        }

        t.test("each launch gets a new session number, and keeps it") {
            // Its own defaults suite so the real one is untouched by a test.
            let defaults = UserDefaults(suiteName: "lumiere.tests.spotlight")!
            defaults.removeObject(forKey: "s")

            let first = Spotlight.beginSession(in: defaults, key: "s")
            let second = Spotlight.beginSession(in: defaults, key: "s")
            t.expectEqual(second, first + 1)
            // Persisted, so quitting and reopening moves on rather than restarting
            // at the same six titles.
            t.expectEqual(defaults.integer(forKey: "s"), second)
        }

        t.test("a new session features a different slice") {
            let pool = (1...10).map { title("p\($0)", rating: 9.0) }
            t.expectEqual(Spotlight.mix([pool], limit: 3, day: 4).map(\.id),
                          ["p5", "p6", "p7"])
            t.expectEqual(Spotlight.mix([pool], limit: 3, day: 5).map(\.id),
                          ["p6", "p7", "p8"])
        }

        t.test("empty in, empty out") {
            t.expectEqual(Spotlight.mix([], limit: 6).count, 0)
            t.expectEqual(Spotlight.mix([[], []], limit: 6).count, 0)
            t.expectEqual(Spotlight.mix([[title("a", rating: 1)]], limit: 0).count, 0)
        }
    }
}
