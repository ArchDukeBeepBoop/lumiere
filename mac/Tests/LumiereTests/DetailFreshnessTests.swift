import Foundation
import TestKit
import LumiereKit

/// When an uncredited detail payload is looked at again.
@MainActor
func registerDetailFreshnessTests(_ t: TestRunner) {

    func item(_ type: String, people: String) -> JellyfinItem {
        let json = """
        {"Id":"a","Name":"X","Type":"\(type)","People":\(people)}
        """
        return try! JellyfinClient.decoder.decode(JellyfinItem.self, from: Data(json.utf8))
    }
    let now = Date(timeIntervalSince1970: 100_000)
    let twentyMinutesAgo = now.addingTimeInterval(-20 * 60)
    let aMinuteAgo = now.addingTimeInterval(-60)

    t.suite("Detail freshness") { t in

        t.test("a film with no cast is stale after a quarter of an hour") {
            t.expect(DetailFreshness.isStaleWithoutCredits(item("Movie", people: "[]"), fetchedAt: twentyMinutesAgo, now: now))
            t.expect(!DetailFreshness.isStaleWithoutCredits(item("Movie", people: "[]"), fetchedAt: aMinuteAgo, now: now))
        }

        t.test("a film with a cast keeps the day") {
            let credited = item("Movie", people: #"[{"Id":"p","Name":"Someone","Type":"Actor"}]"#)
            t.expect(!DetailFreshness.isStaleWithoutCredits(credited, fetchedAt: twentyMinutesAgo, now: now))
        }

        t.test("a folder has no cast to wait for") {
            t.expect(!DetailFreshness.isStaleWithoutCredits(item("Folder", people: "[]"), fetchedAt: twentyMinutesAgo, now: now))
        }
    }
}
