import Foundation
import TestKit
import LumiereKit

/// Which libraries keep frames off their wide cards.
@MainActor
func registerDiscreetArtPolicyTests(_ t: TestRunner) {

    func library(_ id: String, _ name: String) throws -> LibraryRecord {
        let object: [String: Any] = ["Id": id, "Name": name, "Type": "CollectionFolder",
                                     "CollectionType": "tvshows"]
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryRecord(from: item, serverId: "s", sortIndex: 0)
    }

    t.suite("Discreet artwork policy") { t in

        t.test("an adult library is discreet by default and nothing else is") {
            let libs = [try library("h", "Adult"), try library("a", "Anime")]
            t.expectEqual(DiscreetArtPolicy.discreet(libraries: libs, stored: nil), ["h"])
        }

        t.test("a choice overrides the default in both directions") {
            let libs = [try library("h", "Adult"), try library("a", "Anime")]
            let stored = RecentlyAddedPolicy.store(["h": false, "a": true])
            t.expectEqual(DiscreetArtPolicy.discreet(libraries: libs, stored: stored), ["a"])
        }
    }
}

/// Rows switched off on the home screen.
@MainActor
func registerHomeHiddenTests(_ t: TestRunner) {

    t.suite("Home hidden rows") { t in

        t.test("hidden ids round-trip and ignore empties") {
            let ids: Set<String> = ["latest:a", "forgotten"]
            t.expectEqual(HomeOrder.hidden(from: HomeOrder.encodeHidden(ids)), ids)
            t.expectEqual(HomeOrder.hidden(from: ""), [])
            t.expectEqual(HomeOrder.hidden(from: nil), [])
            t.expectEqual(HomeOrder.hidden(from: ",,x,"), ["x"])
        }
    }
}

/// What a library's shelf may draw from.
@MainActor
func registerShelfRulesTests(_ t: TestRunner) {

    func entry(type: String, path: String, minutes: Double? = nil) throws -> LibraryEntry {
        var object: [String: Any] = ["Id": "1", "Name": "X", "Type": type, "Path": path]
        if let minutes { object["RunTimeTicks"] = Int(minutes * 60 * 10_000_000) }
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(item: ItemRecord(from: item, serverId: "s", syncedAt: Date()), userData: nil)
    }

    t.suite("Shelf rules") { t in

        t.test("the default admits everything") {
            let rules = ShelfRules.default
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/a.mp4")), true)
            t.expectEqual(rules.qualifies(try entry(type: "Movie", path: "/L/b.mkv")), true)
        }

        t.test("a kind switched off is refused") {
            var rules = ShelfRules.default
            rules.videos = false
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/a.mp4")), false)
            t.expectEqual(rules.qualifies(try entry(type: "Movie", path: "/L/b.mkv")), true)
        }

        t.test("an excluded folder is matched by name at any depth, ignoring case") {
            var rules = ShelfRules.default
            rules.excludedFolders = ["samples"]
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/Show/Samples/a.mp4")), false)
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/Show/a.mp4")), true)
            // The file's own name is not a folder.
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/Show/samples.mp4")), true)
        }

        t.test("a minimum length ignores files of unknown length") {
            var rules = ShelfRules.default
            rules.minimumMinutes = 10
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/a.mp4", minutes: 3)), false)
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/a.mp4", minutes: 30)), true)
            t.expectEqual(rules.qualifies(try entry(type: "Video", path: "/L/a.mp4")), true)
        }

        t.test("rules round-trip through storage and a library without any gets the default") {
            var rules = ShelfRules.default
            rules.excludedFolders = ["Extras"]
            let stored = ShelfRules.encode(["lib": rules])
            let back = ShelfRules.all(from: stored)
            t.expectEqual(back["lib"], rules)
            t.expectEqual(ShelfRules.rules(for: "other", in: back), .default)
            t.expectEqual(ShelfRules.rules(for: nil, in: back), .default)
        }
    }
}

/// Which credits marks the player believes.
@MainActor
func registerSegmentTrustTests(_ t: TestRunner) {

    let episode = 24.0 * 60
    let film = 120.0 * 60

    t.suite("Segment trust") { t in

        t.test("credits in the last two minutes of an episode are believed") {
            t.expectEqual(SegmentTrust.isPlausibleOutro(
                start: episode - 100, end: episode - 10, duration: episode), true)
        }

        t.test("a mark five minutes before the end of an episode is not credits") {
            t.expectEqual(SegmentTrust.isPlausibleOutro(
                start: episode - 5 * 60, end: episode - 3.5 * 60, duration: episode), false)
        }

        t.test("the floor is the viewer's: widen it and the same mark is believed") {
            t.expectEqual(SegmentTrust.isPlausibleOutro(
                start: episode - 5 * 60, end: episode - 3.5 * 60,
                duration: episode, floorMinutes: 6), true)
        }

        t.test("a film's credits may begin fifteen minutes out") {
            t.expectEqual(SegmentTrust.isPlausibleOutro(
                start: film - 15 * 60, end: film, duration: film), true)
            t.expectEqual(SegmentTrust.isPlausibleOutro(
                start: film - 25 * 60, end: film, duration: film), false)
        }

        t.test("an ending theme followed by a preview is still credits") {
            // Ends ninety seconds before the file does; begins where it should.
            t.expectEqual(SegmentTrust.isPlausibleOutro(
                start: episode - 3 * 60, end: episode - 90, duration: episode), true)
        }

        t.test("no duration, no belief") {
            t.expectEqual(SegmentTrust.isPlausibleOutro(start: 10, end: 20, duration: 0), false)
        }
    }
}

/// Episodes in the order the files say.
@MainActor
func registerEpisodeOrderTests(_ t: TestRunner) {

    func episode(_ file: String, title: String, index: Int?) throws -> LibraryEntry {
        var object: [String: Any] = ["Id": file, "Name": title, "Type": "Episode",
                                     "Path": "/m/Show/Season 1/" + file]
        if let index { object["IndexNumber"] = index }
        let data = try JSONSerialization.data(withJSONObject: object)
        let item = try JellyfinClient.decoder.decode(JellyfinItem.self, from: data)
        return LibraryEntry(item: ItemRecord(from: item, serverId: "s", syncedAt: Date()), userData: nil)
    }

    t.suite("Episode order") { t in

        t.test("filenames win over scraped titles") {
            let eps = [
                try episode("Show - 02.mkv", title: "Pilot", index: 2),
                try episode("Show - 10.mkv", title: "Aftermath", index: 10),
                try episode("Show - 01.mkv", title: "The Night of the Comet", index: 1),
            ]
            let names = eps.orderedAsEpisodes(byFilename: true).map(\.item.name)
            t.expectEqual(names, ["The Night of the Comet", "Pilot", "Aftermath"])
        }

        t.test("ten follows nine, the way Finder sorts") {
            let eps = [
                try episode("Show - 10.mkv", title: "x", index: nil),
                try episode("Show - 9.mkv", title: "y", index: nil),
            ]
            t.expectEqual(eps.orderedAsEpisodes(byFilename: true).map(\.item.name), ["y", "x"])
        }

        t.test("off, the number decides and the unnumbered go last") {
            let eps = [
                try episode("b.mkv", title: "Beta", index: nil),
                try episode("c.mkv", title: "Gamma", index: 2),
                try episode("a.mkv", title: "Alpha", index: 1),
            ]
            t.expectEqual(eps.orderedAsEpisodes(byFilename: false).map(\.item.name),
                          ["Alpha", "Gamma", "Beta"])
        }
    }
}
