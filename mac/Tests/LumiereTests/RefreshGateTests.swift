import Foundation
import TestKit
import LumiereKit

@MainActor
func registerRefreshGateTests(_ t: TestRunner) async {
    t.suite("Weekly summary") { t in
        let week = Date(timeIntervalSince1970: 0)
        let last = WeeklySummary.Snapshot(at: week, counts: ["Unreadable": 4, "subtitlesDone": 10, "MissingEpisodes": 132])
        t.test("it says what changed, good and bad") {
            let now = WeeklySummary.Snapshot(at: week.addingTimeInterval(8 * 86400),
                                             counts: ["Unreadable": 2, "subtitlesDone": 15, "MissingEpisodes": 133])
            t.expectEqual(WeeklySummary.message(from: last, to: now),
                          "This week: 5 subtitles fetched, 1 new missing episode, 2 unreadable files fixed.")
        }
        t.test("a quiet week says nothing, and the first run is a baseline") {
            t.expect(WeeklySummary.message(from: last, to: last) == nil)
            t.expect(!WeeklySummary.isDue(last: nil))
            t.expect(WeeklySummary.isDue(last: last, now: week.addingTimeInterval(7 * 86400)))
        }
    }

    await t.suite("Refresh gate") { t in
        await t.test("requests during a refresh fold into one more, not one each") {
            let gate = RefreshGate()
            var runs = 0
            let slow: @MainActor () async -> Void = {
                runs += 1
                try? await Task.sleep(for: .milliseconds(80))
            }
            let first = Task { @MainActor in await gate.request(slow) }
            try? await Task.sleep(for: .milliseconds(10))
            // Three more announcements while the first is still running.
            for _ in 0..<3 { await gate.request(slow) }
            await first.value
            t.expectEqual(runs, 2)
        }
    }
}
