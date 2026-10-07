import Foundation
import TestKit
import LumiereKit

@MainActor
func registerSeasonNeighbourTests(_ t: TestRunner) {
    t.suite("Auto-skip") { t in
        t.test("the third skip in a season turns it on, for that season only") {
            let defaults = UserDefaults(suiteName: "lumiere.tests.autoskip")!
            defaults.removePersistentDomain(forName: "lumiere.tests.autoskip")
            for _ in 0..<2 { AutoSkip.record("s1", in: defaults) }
            t.expect(!AutoSkip.isOn(for: "s1", in: defaults))
            AutoSkip.record("s1", in: defaults)
            t.expect(AutoSkip.isOn(for: "s1", in: defaults))
            t.expect(!AutoSkip.isOn(for: "s2", in: defaults))
        }
    }

    t.suite("Watched at credits") { t in
        let credits = [(start: 1320.0, end: 1410.0)]
        t.test("stopping in the credits counts; before them does not") {
            t.expect(WatchedAtCredits.counts(position: 1330, duration: 1420, outroStarts: credits, floorMinutes: 3))
            t.expect(!WatchedAtCredits.counts(position: 1300, duration: 1420, outroStarts: credits, floorMinutes: 3))
        }
        t.test("without credits, the last 5% counts") {
            t.expect(WatchedAtCredits.counts(position: 1360, duration: 1420, outroStarts: [], floorMinutes: 3))
            t.expect(!WatchedAtCredits.counts(position: 1200, duration: 1420, outroStarts: [], floorMinutes: 3))
        }
        t.test("a credits segment that begins mid-episode is not believed") {
            let early = [(start: 300.0, end: 400.0)]
            t.expect(!WatchedAtCredits.counts(position: 350, duration: 1420, outroStarts: early, floorMinutes: 3))
        }
    }

    t.suite("Season neighbours") { t in
        let seasons = [season("s1", 1), season("s2", 2), season("sp", 0), season("s3", 3)]

        t.test("the last of season one leads to season two") {
            t.expectEqual(SeasonNeighbours.following("s1", in: seasons, includesSpecials: false)?.id, "s2")
        }
        t.test("specials are stepped over unless asked for") {
            t.expectEqual(SeasonNeighbours.following("s2", in: seasons, includesSpecials: false)?.id, "s3")
            t.expectEqual(SeasonNeighbours.following("s2", in: seasons, includesSpecials: true)?.id, "sp")
        }
        t.test("the ends have nothing beyond them") {
            t.expect(SeasonNeighbours.following("s3", in: seasons, includesSpecials: false) == nil)
            t.expect(SeasonNeighbours.preceding("s1", in: seasons, includesSpecials: false) == nil)
        }
        t.test("watching the specials themselves still steps on") {
            t.expectEqual(SeasonNeighbours.following("sp", in: seasons, includesSpecials: false)?.id, "s3")
        }
    }
}

private func season(_ id: String, _ number: Int) -> LibraryEntry {
    let json: [String: Any] = ["Id": id, "Name": "S\(number)", "Type": "Season", "IndexNumber": number]
    let data = try! JSONSerialization.data(withJSONObject: json)
    let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
    return LibraryEntry(item: ItemRecord(from: decoded, serverId: "s", syncedAt: Date()), userData: nil)
}
