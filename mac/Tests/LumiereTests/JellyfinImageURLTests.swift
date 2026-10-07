import Foundation
import TestKit
import LumiereKit

@MainActor
func registerJellyfinImageURLTests(_ t: TestRunner) {
    let server = URL(string: "http://192.168.60.40:8096")!

    t.suite("Jellyfin image URLs") { t in

        t.test("builds a poster URL with tag, size and quality") {
            let url = JellyfinImageURL.url(
                serverURL: server,
                itemId: "abc123",
                kind: .primary,
                tag: "deadbeef",
                maxWidth: 300
            )
            t.expectEqual(
                url?.absoluteString,
                "http://192.168.60.40:8096/Items/abc123/Images/Primary?tag=deadbeef&maxWidth=300&quality=90"
            )
        }

        t.test("omits maxWidth when asking for the original") {
            let url = JellyfinImageURL.url(
                serverURL: server, itemId: "abc", kind: .backdrop, tag: "t", maxWidth: nil
            )
            t.expect(url?.absoluteString.contains("maxWidth") == false)
        }

        t.test("includes the backdrop index when given") {
            let url = JellyfinImageURL.url(
                serverURL: server, itemId: "abc", kind: .backdrop, tag: "t",
                maxWidth: 1280, index: 0
            )
            t.expect(url?.path == "/Items/abc/Images/Backdrop/0")
        }

        t.test("cache key separates decode sizes of the same image") {
            let small = JellyfinImageURL.cacheKey(itemId: "a", kind: .primary, tag: "t", maxWidth: 300)
            let large = JellyfinImageURL.cacheKey(itemId: "a", kind: .primary, tag: "t", maxWidth: 900)
            t.expect(small != large)
        }

        t.test("cache key changes when the artwork tag changes") {
            let before = JellyfinImageURL.cacheKey(itemId: "a", kind: .primary, tag: "old", maxWidth: 300)
            let after = JellyfinImageURL.cacheKey(itemId: "a", kind: .primary, tag: "new", maxWidth: 300)
            t.expect(before != after)
        }
    }

    t.suite("Item artwork fallbacks") { t in

        t.test("an episode with no poster falls back to the series poster") {
            let episode = makeItem(
                id: "ep1", type: "Episode", seriesId: "show1",
                seriesPrimaryImageTag: "seriesTag"
            )
            let source = episode.posterSource()
            t.expectEqual(source?.itemId, "show1")
            t.expectEqual(source?.tag, "seriesTag")
        }

        t.test("an item with its own poster uses it") {
            let movie = makeItem(id: "m1", type: "Movie", imageTags: ["Primary": "own"])
            let source = movie.posterSource()
            t.expectEqual(source?.itemId, "m1")
            t.expectEqual(source?.tag, "own")
        }

        t.test("no artwork anywhere returns nil rather than a broken URL") {
            let bare = makeItem(id: "x", type: "Movie")
            t.expectNil(bare.posterSource())
            t.expectNil(bare.backdropSource())
        }

        t.test("backdrop prefers the item's own over the parent's") {
            let item = makeItem(
                id: "ep1", type: "Episode",
                imageTags: ["Thumb": "ownThumb"],
                backdropImageTags: ["ownBackdrop"],
                parentBackdropItemId: "show1",
                parentBackdropImageTags: ["parentBackdrop"]
            )
            let source = item.backdropSource()
            t.expectEqual(source?.itemId, "ep1")
            t.expectEqual(source?.tag, "ownBackdrop")
        }

        t.test("an episode with only a primary image uses it as the wide image") {
            let item = makeItem(id: "ep1", type: "Episode", imageTags: ["Primary": "still"])
            let source = item.backdropSource()
            t.expectEqual(source?.itemId, "ep1")
            t.expectEqual(source?.tag, "still")
        }

        t.test("an episode falls back to the series backdrop") {
            let item = makeItem(
                id: "ep1", type: "Episode",
                parentBackdropItemId: "show1",
                parentBackdropImageTags: ["parentBackdrop"]
            )
            let source = item.backdropSource()
            t.expectEqual(source?.itemId, "show1")
            t.expectEqual(source?.tag, "parentBackdrop")
        }
    }

    t.suite("Item display text") { t in

        t.test("episodes lead with the series name") {
            let episode = makeItem(
                id: "e", type: "Episode", seriesName: "Severance",
                indexNumber: 4, parentIndexNumber: 2
            )
            t.expectEqual(episode.displayTitle, "Severance")
            t.expectEqual(episode.subtitleLine, "S2 E4")
        }

        t.test("an episode with no numbering degrades to the series name") {
            let episode = makeItem(id: "e", type: "Episode", seriesName: "Severance")
            t.expectEqual(episode.subtitleLine, "Severance")
        }

        t.test("movies show the year") {
            let movie = makeItem(id: "m", type: "Movie", productionYear: 2017)
            t.expectEqual(movie.subtitleLine, "2017")
        }

        t.test("runtime converts from ticks to seconds") {
            let movie = makeItem(id: "m", type: "Movie", runTimeTicks: 98_400_000_000)
            t.expectEqual(movie.runtimeSeconds, 9840)
        }

        t.test("zero or missing runtime ticks reads as unknown, not zero") {
            t.expectNil(makeItem(id: "m", type: "Movie", runTimeTicks: 0).runtimeSeconds)
            t.expectNil(makeItem(id: "m", type: "Movie").runtimeSeconds)
        }
    }
}

/// Builds a `JellyfinItem` by round-tripping JSON, so the tests exercise the real
/// decoder rather than a hand-built value that could drift from it.
@MainActor
private func makeItem(
    id: String,
    type: String,
    seriesId: String? = nil,
    seriesName: String? = nil,
    seriesPrimaryImageTag: String? = nil,
    indexNumber: Int? = nil,
    parentIndexNumber: Int? = nil,
    productionYear: Int? = nil,
    runTimeTicks: Int64? = nil,
    imageTags: [String: String]? = nil,
    backdropImageTags: [String]? = nil,
    parentBackdropItemId: String? = nil,
    parentBackdropImageTags: [String]? = nil
) -> JellyfinItem {
    var json: [String: Any] = ["Id": id, "Name": "Test", "Type": type]
    if let seriesId { json["SeriesId"] = seriesId }
    if let seriesName { json["SeriesName"] = seriesName }
    if let seriesPrimaryImageTag { json["SeriesPrimaryImageTag"] = seriesPrimaryImageTag }
    if let indexNumber { json["IndexNumber"] = indexNumber }
    if let parentIndexNumber { json["ParentIndexNumber"] = parentIndexNumber }
    if let productionYear { json["ProductionYear"] = productionYear }
    if let runTimeTicks { json["RunTimeTicks"] = runTimeTicks }
    if let imageTags { json["ImageTags"] = imageTags }
    if let backdropImageTags { json["BackdropImageTags"] = backdropImageTags }
    if let parentBackdropItemId { json["ParentBackdropItemId"] = parentBackdropItemId }
    if let parentBackdropImageTags { json["ParentBackdropImageTags"] = parentBackdropImageTags }

    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
}
