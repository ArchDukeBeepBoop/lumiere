import Foundation
import TestKit
import LumiereKit

/// The one watched rule every tile and button now shares.
@MainActor
func registerWatchedRuleTests(_ t: TestRunner) {
    t.suite("Watched rule") { t in

        t.test("a finished show whose own flag was never set reads as watched") {
            // The case that kept "Mark as Watched" on a show already watched:
            // the server leaves a show's flag unset and says so by its count.
            let show = entry("Series", played: false, unplayed: 0)
            t.expect(show.isPlayed)
            t.expect(!show.showsUnwatchedMarker)
        }

        t.test("a season with episodes left is marked; a film follows its flag") {
            t.expect(entry("Season", played: false, unplayed: 3).showsUnwatchedMarker)
            t.expect(entry("Movie", played: false, unplayed: nil).showsUnwatchedMarker)
            t.expect(!entry("Movie", played: true, unplayed: nil).showsUnwatchedMarker)
        }

        t.test("a folder has no watched state to mark") {
            t.expect(!entry("Folder", played: false, unplayed: 5).showsUnwatchedMarker)
        }
    }
}

private func entry(_ type: String, played: Bool, unplayed: Int?) -> LibraryEntry {
    let json: [String: Any] = ["Id": "x", "Name": "x", "Type": type]
    let data = try! JSONSerialization.data(withJSONObject: json)
    let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
    var user = UserDataRecord(itemId: "x", from: nil, updatedAt: Date())
    user.played = played
    user.unplayedItemCount = unplayed
    return LibraryEntry(item: ItemRecord(from: decoded, serverId: "s", syncedAt: Date()), userData: user)
}
