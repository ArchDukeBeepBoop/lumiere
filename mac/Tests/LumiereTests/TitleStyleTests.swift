import Foundation
import TestKit
import LumiereKit

@MainActor
func registerTitleStyleTests(_ t: TestRunner) {

    func item(
        name: String,
        type: String = "Movie",
        year: Int? = nil,
        series: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        path: String? = nil,
        seasons: Int? = nil
    ) -> ItemRecord {
        var json: [String: Any] = ["Id": "x", "Name": name, "Type": type]
        if let year { json["ProductionYear"] = year }
        if let series { json["SeriesName"] = series }
        if let season { json["ParentIndexNumber"] = season }
        if let episode { json["IndexNumber"] = episode }
        if let path { json["Path"] = path }
        if let seasons { json["ChildCount"] = seasons }

        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return ItemRecord(from: decoded, serverId: "s1", syncedAt: Date())
    }

    t.suite("Title style · metadata title") { t in

        t.test("a film reads as its name") {
            let movie = item(name: "Blade Runner 2049", year: 2017)
            t.expectEqual(TitleFormatter.title(for: movie, style: .metadataTitle), "Blade Runner 2049")
            t.expectEqual(TitleFormatter.subtitle(for: movie, style: .metadataTitle), "2017")
        }

        t.test("an episode reads as its own name with the season line beneath") {
            let episode = item(
                name: "Pilot", type: "Episode", series: "Rick and Morty",
                season: 1, episode: 1
            )
            t.expectEqual(TitleFormatter.title(for: episode, style: .metadataTitle), "Pilot")
            t.expectEqual(TitleFormatter.subtitle(for: episode, style: .metadataTitle), "S1 E1")
        }

        t.test("a series counts its seasons rather than repeating the year") {
            let series = item(name: "Severance", type: "Series", year: 2022, seasons: 2)
            t.expectEqual(TitleFormatter.subtitle(for: series, style: .metadataTitle), "2 seasons")
        }

        t.test("a one-season series is singular") {
            let series = item(name: "Chernobyl", type: "Series", seasons: 1)
            t.expectEqual(TitleFormatter.subtitle(for: series, style: .metadataTitle), "1 season")
        }
    }

    t.suite("Title style · metadata filename") { t in

        t.test("an episode follows the Series - 1x01 - Title scheme") {
            let episode = item(
                name: "Pilot", type: "Episode", series: "Rick and Morty",
                season: 1, episode: 1, path: "/media/rm/whatever.mkv"
            )
            t.expectEqual(
                TitleFormatter.title(for: episode, style: .metadataFilename),
                "Rick and Morty - 1x01 - Pilot.mkv"
            )
        }

        t.test("episode numbers are zero-padded to two digits, seasons are not") {
            let episode = item(
                name: "Finale", type: "Episode", series: "Show",
                season: 10, episode: 7, path: "/media/x.mp4"
            )
            t.expectEqual(
                TitleFormatter.title(for: episode, style: .metadataFilename),
                "Show - 10x07 - Finale.mp4"
            )
        }

        t.test("a film follows Title (Year)") {
            let movie = item(name: "Dune", year: 2021, path: "/media/dune.mkv")
            t.expectEqual(TitleFormatter.title(for: movie, style: .metadataFilename), "Dune (2021).mkv")
        }

        t.test("the extension comes from the real path, never guessed") {
            let mp4 = item(name: "Dune", year: 2021, path: "/media/dune.mp4")
            t.expect(TitleFormatter.title(for: mp4, style: .metadataFilename).hasSuffix(".mp4"))

            // No path cached: better a name with no extension than a wrong one.
            let unknown = item(name: "Dune", year: 2021)
            t.expectEqual(TitleFormatter.title(for: unknown, style: .metadataFilename), "Dune (2021)")
        }

        t.test("a film with no year keeps just its name") {
            let movie = item(name: "Untitled", path: "/media/untitled.mkv")
            t.expectEqual(TitleFormatter.title(for: movie, style: .metadataFilename), "Untitled.mkv")
        }

        t.test("an episode with no numbering still produces something readable") {
            let episode = item(
                name: "Special", type: "Episode", series: "Show", path: "/media/s.mkv"
            )
            t.expectEqual(
                TitleFormatter.title(for: episode, style: .metadataFilename),
                "Show - Special.mkv"
            )
        }

        t.test("the subtitle drops to the plain title so the lines don't repeat") {
            let episode = item(
                name: "Pilot", type: "Episode", series: "Rick and Morty",
                season: 1, episode: 1, path: "/media/x.mkv"
            )
            t.expectEqual(
                TitleFormatter.subtitle(for: episode, style: .metadataFilename),
                "S1 E1 · Pilot"
            )
        }
    }

    t.suite("Title style · original filename") { t in

        t.test("shows exactly what is on disk, release tags and all") {
            let episode = item(
                name: "Pilot", type: "Episode", series: "Rick and Morty",
                season: 1, episode: 1,
                path: "/mnt/tv/Rick.and.Morty.S01E01.1080p.WEB-DL.DDP5.1.H.264-NTb.mkv"
            )
            t.expectEqual(
                TitleFormatter.title(for: episode, style: .originalFilename),
                "Rick.and.Morty.S01E01.1080p.WEB-DL.DDP5.1.H.264-NTb.mkv"
            )
        }

        t.test("strips the directory, keeps the name") {
            let movie = item(name: "Dune", year: 2021, path: "/a/b/c/Dune.2021.2160p.mkv")
            t.expectEqual(
                TitleFormatter.title(for: movie, style: .originalFilename),
                "Dune.2021.2160p.mkv"
            )
        }

        t.test("falls back to the metadata filename when no path was cached") {
            // Items synced before the path column existed have none.
            let movie = item(name: "Dune", year: 2021)
            t.expectEqual(
                TitleFormatter.title(for: movie, style: .originalFilename),
                "Dune (2021)"
            )
        }

        t.test("an empty path is treated as no path") {
            let movie = item(name: "Dune", year: 2021, path: "")
            t.expectEqual(
                TitleFormatter.title(for: movie, style: .originalFilename),
                "Dune (2021)"
            )
        }

        t.test("a tidied library makes both filename styles agree") {
            // The reason both exist: on a renamed library they converge, and on a
            // messy one they diverge usefully.
            let episode = item(
                name: "Pilot", type: "Episode", series: "Rick and Morty",
                season: 1, episode: 1,
                path: "/mnt/tv/Rick and Morty/Season 1/Rick and Morty - 1x01 - Pilot.mkv"
            )
            t.expectEqual(
                TitleFormatter.title(for: episode, style: .originalFilename),
                TitleFormatter.title(for: episode, style: .metadataFilename)
            )
        }
    }
}
