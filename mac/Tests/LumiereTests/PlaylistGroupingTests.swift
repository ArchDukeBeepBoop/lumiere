import Foundation
import TestKit
import LumiereKit

/// How a playlist's rows collapse — and, more importantly, when they must not.
@MainActor
func registerPlaylistGroupingTests(_ t: TestRunner) {

    func entry(
        id: String,
        name: String,
        seriesId: String? = nil,
        seriesName: String? = nil
    ) -> LibraryEntry {
        var json: [String: Any] = ["Id": id, "Name": name, "Type": "Episode"]
        if let seriesId { json["SeriesId"] = seriesId }
        if let seriesName { json["SeriesName"] = seriesName }
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: Date()),
            userData: nil
        )
    }

    func movie(id: String, name: String) -> LibraryEntry {
        let json: [String: Any] = ["Id": id, "Name": name, "Type": "Movie"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(
            item: ItemRecord(from: decoded, serverId: "s1", syncedAt: Date()),
            userData: nil
        )
    }

    t.suite("Playlist grouping") { t in

        t.test("several episodes of one series collapse to a single row") {
            let rows = PlaylistGrouping.rows(for: [
                entry(id: "1", name: "Ep 1", seriesId: "S", seriesName: "My Show"),
                entry(id: "2", name: "Ep 2", seriesId: "S", seriesName: "My Show"),
                entry(id: "3", name: "Ep 3", seriesId: "S", seriesName: "My Show"),
            ])
            t.expectEqual(rows.count, 1)
            guard case .series(_, let name, let episodes) = rows[0] else {
                return t.expect(false, "expected a series row")
            }
            t.expectEqual(name, "My Show")
            t.expectEqual(episodes.count, 3)
        }

        t.test("a lone episode stays itself, because that one was chosen") {
            // The whole point of the rule: one episode from a series means someone
            // picked that episode. Hiding it under a series heading would bury it.
            let rows = PlaylistGrouping.rows(for: [
                entry(id: "1", name: "The Good One", seriesId: "S", seriesName: "My Show"),
            ])
            t.expectEqual(rows.count, 1)
            guard case .item(let single) = rows[0] else {
                return t.expect(false, "a single episode must not be grouped")
            }
            t.expectEqual(single.item.name, "The Good One")
        }

        t.test("a grouped series and a lone episode coexist") {
            let rows = PlaylistGrouping.rows(for: [
                entry(id: "1", name: "A1", seriesId: "A", seriesName: "Show A"),
                entry(id: "2", name: "A2", seriesId: "A", seriesName: "Show A"),
                entry(id: "3", name: "B1", seriesId: "B", seriesName: "Show B"),
            ])
            t.expectEqual(rows.count, 2)
            guard case .series = rows[0] else { return t.expect(false, "A should group") }
            guard case .item = rows[1] else { return t.expect(false, "B should not group") }
        }

        t.test("the playlist's own order is preserved") {
            // A playlist is a sequence; re-sorting destroys the only thing it
            // encodes. A series takes the position of its first episode.
            let rows = PlaylistGrouping.rows(for: [
                movie(id: "m1", name: "Opening Film"),
                entry(id: "1", name: "A1", seriesId: "A", seriesName: "Show A"),
                movie(id: "m2", name: "Interlude"),
                entry(id: "2", name: "A2", seriesId: "A", seriesName: "Show A"),
            ])
            t.expectEqual(rows.count, 3)
            guard case .item(let first) = rows[0] else { return t.expect(false, "1st") }
            t.expectEqual(first.item.name, "Opening Film")
            guard case .series(_, _, let episodes) = rows[1] else { return t.expect(false, "2nd") }
            t.expectEqual(episodes.map(\.item.name), ["A1", "A2"])
            guard case .item(let third) = rows[2] else { return t.expect(false, "3rd") }
            t.expectEqual(third.item.name, "Interlude")
        }

        t.test("items with no series are never grouped") {
            let rows = PlaylistGrouping.rows(for: [
                movie(id: "m1", name: "Film One"),
                movie(id: "m2", name: "Film Two"),
            ])
            t.expectEqual(rows.count, 2)
        }

        t.test("an empty playlist yields no rows") {
            t.expect(PlaylistGrouping.rows(for: []).isEmpty)
        }
    }
}
