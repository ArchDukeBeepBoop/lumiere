import Foundation
import TestKit
import LumiereKit

/// Why the hero is showing what it is showing.
@MainActor
func registerSpotlightReasonTests(_ t: TestRunner) {

    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let day: TimeInterval = 24 * 60 * 60

    /// One candidate, described by the few things the judgement reads.
    func entry(
        type: String = "Movie",
        runtime: Double = 6000,
        position: Double = 0,
        played: Bool = false,
        lastPlayed: Date? = nil,
        unplayed: Int? = nil,
        rating: Double? = nil
    ) throws -> LibraryEntry {
        var object: [String: Any] = ["Id": "1", "Name": "A Title", "Type": type]
        object["RunTimeTicks"] = Int(runtime * 10_000_000)
        if let rating { object["CommunityRating"] = rating }
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        let record = ItemRecord(from: item, serverId: "s1", syncedAt: now)

        var userData = UserDataRecord(itemId: "1", from: nil, updatedAt: now)
        userData.played = played
        userData.playbackPositionTicks = Int64(position * 10_000_000)
        userData.lastPlayedDate = lastPlayed
        userData.unplayedItemCount = unplayed
        return LibraryEntry(item: record, userData: userData)
    }

    t.suite("Spotlight reason") { t in

        t.test("something left unfinished a while ago is the strongest offer") {
            // Half an hour into a hundred-minute film, three weeks ago.
            let abandoned = try entry(
                position: 1800, lastPlayed: now.addingTimeInterval(-21 * day)
            )
            let verdict = SpotlightReason.verdict(for: abandoned, now: now)
            t.expectEqual(verdict.kind, .abandoned)
            t.expectEqual(verdict.sentence, "You stopped 30 minutes in, three weeks ago")
        }

        t.test("something left yesterday is not abandoned") {
            // Still in progress. Continue Watching has it; the hero should not
            // claim you forgot about it.
            let recent = try entry(position: 1800, lastPlayed: now.addingTimeInterval(-day))
            t.expectEqual(SpotlightReason.verdict(for: recent, now: now).kind, .none)
        }

        t.test("something nearly over is not abandoned either") {
            // 95% through is a film you finished and stopped before the credits.
            let nearlyOver = try entry(
                position: 5700, lastPlayed: now.addingTimeInterval(-30 * day)
            )
            t.expectEqual(SpotlightReason.verdict(for: nearlyOver, now: now).kind, .none)
        }

        t.test("a season with a few episodes left says so") {
            let series = try entry(
                type: "Series", lastPlayed: now.addingTimeInterval(-3 * day), unplayed: 3
            )
            let verdict = SpotlightReason.verdict(for: series, now: now)
            t.expectEqual(verdict.kind, .nearlyDone)
            t.expectEqual(verdict.sentence, "three episodes left")
        }

        t.test("a series nobody has started is not nearly done") {
            // Three episodes remaining out of three is not an achievement.
            let untouched = try entry(type: "Series", unplayed: 3)
            t.expect(SpotlightReason.verdict(for: untouched, now: now).kind != .nearlyDone)
        }

        t.test("a highly rated title never opened is worth featuring") {
            let unseen = try entry(rating: 8.6)
            let verdict = SpotlightReason.verdict(for: unseen, now: now)
            t.expectEqual(verdict.kind, .bestUnseen)
            t.expectEqual(verdict.sentence, "Rated 9, and you have never opened it")
        }

        t.test("a mediocre unseen title gets no sentence") {
            // The claim has to be worth making. "Rated 6.1" is not a reason.
            let dull = try entry(rating: 6.1)
            t.expectEqual(SpotlightReason.verdict(for: dull, now: now).kind, .none)
            t.expectNil(SpotlightReason.verdict(for: dull, now: now).sentence)
        }

        t.test("the strongest reason in the pool wins") {
            let pool = [
                try entry(rating: 9.4),
                try entry(type: "Series", lastPlayed: now.addingTimeInterval(-2 * day), unplayed: 2),
                try entry(position: 2400, lastPlayed: now.addingTimeInterval(-40 * day)),
            ]
            let chosen = SpotlightReason.choose(from: pool, now: now)
            // Not the 9.4: something you already started outranks something you
            // have only been told is good.
            t.expectEqual(chosen?.verdict.kind, .abandoned)
        }

        t.test("rotation happens among equals, never across them") {
            let strong = try entry(position: 2400, lastPlayed: now.addingTimeInterval(-40 * day))
            let weak = try entry(rating: 9.9)
            for turn in 0..<6 {
                let chosen = SpotlightReason.choose(from: [strong, weak], now: now, tiebreak: turn)
                t.expectEqual(chosen?.verdict.kind, .abandoned)
            }
        }

        t.test("an empty library features nothing rather than crashing") {
            t.expectNil(SpotlightReason.choose(from: [], now: now))
        }

        t.test("the phrasing reads like a sentence") {
            t.expectEqual(SpotlightReason.minutesPhrase(90), "2 minutes")
            t.expectEqual(SpotlightReason.minutesPhrase(3600), "an hour")
            t.expectEqual(SpotlightReason.minutesPhrase(4200), "an hour and 10 minutes")
            t.expectEqual(SpotlightReason.minutesPhrase(7800), "2 hours and 10 minutes")
            // Never "0 minutes" — a few seconds in is still "1 minute".
            t.expectEqual(SpotlightReason.minutesPhrase(20), "1 minutes")

            t.expectEqual(SpotlightReason.agoPhrase(now.addingTimeInterval(-3 * day), now: now), "3 days ago")
            t.expectEqual(SpotlightReason.agoPhrase(now.addingTimeInterval(-21 * day), now: now), "three weeks ago")
            t.expectEqual(SpotlightReason.agoPhrase(now.addingTimeInterval(-40 * day), now: now), "last month")
            t.expectEqual(SpotlightReason.agoPhrase(now.addingTimeInterval(-500 * day), now: now), "over a year ago")
        }
    }
}
