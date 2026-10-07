import Foundation
import TestKit
import LumiereKit

/// The arithmetic a paged music listing depends on.
///
/// Small, but it is the part that fails quietly: a total that comes back nil, or a
/// page that returns nothing while the total still claims more, both look like a
/// working list right up until it stops loading or never stops asking.
@MainActor
func registerMusicPageTests(_ t: TestRunner) {
    t.suite("Music page") { t in

        func entries(_ count: Int, from start: Int = 0) -> [LibraryEntry] {
            (start..<(start + count)).map { index in
                let json: [String: Any] = [
                    "Id": "t\(index)", "Name": "Track \(index)", "Type": "Audio",
                ]
                let data = try! JSONSerialization.data(withJSONObject: json)
                let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
                return LibraryEntry(
                    item: ItemRecord(from: decoded, serverId: "s1", syncedAt: Date()),
                    userData: nil
                )
            }
        }

        t.test("a page knows there is more behind it") {
            let page = MusicPage(entries: entries(200), total: 4_312)
            t.expectEqual(page.entries.count, 200)
            t.expect(page.entries.count < page.total)
        }

        t.test("an empty page is not a listing of nothing") {
            // The distinction the browser acts on: `empty` means "no rows and none
            // claimed", which ends paging. A short page with a large total does not.
            t.expectEqual(MusicPage.empty.total, 0)
            t.expect(MusicPage.empty.entries.isEmpty)
        }

        t.test("appending pages reaches the total exactly once") {
            // Three windows of a 450-row listing. The browser stops when the loaded
            // count reaches the total; an off-by-one either drops the tail or asks
            // for a page past the end forever.
            var loaded: [LibraryEntry] = []
            let total = 450
            var requests = 0
            while loaded.count < total {
                let offset = loaded.count
                let size = min(200, total - offset)
                loaded += entries(size, from: offset)
                requests += 1
            }
            t.expectEqual(loaded.count, total)
            t.expectEqual(requests, 3)
            t.expectEqual(Set(loaded.map(\.id)).count, total)
        }
    }
}
