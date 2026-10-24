import Foundation
import TestKit
import LumiereKit


/// The values behind the player sidebar: a show's preset and bookmarks round
/// trip through defaults, picture values clamp and convert as mpv expects,
/// and every sound preset but Flat names a filter.
@MainActor
func registerPlayerSidebarTests(_ t: TestRunner) {

    func scratchDefaults() -> UserDefaults {
        let name = "lumiere-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    t.suite("Show presets") { t in
        t.test("a preset comes back for its show and no other") {
            let defaults = scratchDefaults()
            var preset = ShowPreset()
            preset.subtitleDelay = -0.4
            preset.subtitlePosition = 90
            ShowPreset.save(preset, for: "series-1", in: defaults)
            t.expectEqual(ShowPreset.load(for: "series-1", in: defaults), preset)
            t.expectEqual(ShowPreset.load(for: "series-2", in: defaults), nil)
            t.expectEqual(ShowPreset.count(in: defaults), 1)
        }
        t.test("forgetting removes it") {
            let defaults = scratchDefaults()
            ShowPreset.save(ShowPreset(), for: "s", in: defaults)
            ShowPreset.save(nil, for: "s", in: defaults)
            t.expectEqual(ShowPreset.count(in: defaults), 0)
        }
        t.test("a picture survives the trip inside a preset") {
            var picture = PictureAdjustments()
            picture.brightness = 12
            picture.rotateClockwise()
            var preset = ShowPreset()
            preset.picture = try? JSONEncoder().encode(picture)
            let defaults = scratchDefaults()
            ShowPreset.save(preset, for: "x", in: defaults)
            let back = ShowPreset.load(for: "x", in: defaults)?.picture
                .flatMap { try? JSONDecoder().decode(PictureAdjustments.self, from: $0) }
            t.expectEqual(back, picture)
        }
    }

    t.suite("Bookmarks") { t in
        t.test("kept in time order, per file") {
            let defaults = scratchDefaults()
            Bookmarks.save([Bookmark(seconds: 90, label: "B"), Bookmark(seconds: 10, label: "A")],
                           for: "item", in: defaults)
            t.expectEqual(Bookmarks.all(for: "item", in: defaults).map(\.label), ["A", "B"])
            t.expect(Bookmarks.all(for: "other", in: defaults).isEmpty, "another file has none")
        }
        t.test("saving none forgets the file") {
            let defaults = scratchDefaults()
            Bookmarks.save([Bookmark(seconds: 1, label: "x")], for: "i", in: defaults)
            Bookmarks.save([], for: "i", in: defaults)
            t.expect(defaults.dictionary(forKey: Bookmarks.storageKey)?["i"] == nil, "no empty entry left")
        }
    }

    t.suite("Picture and sound") { t in
        t.test("rotation turns a quarter at a time and comes round") {
            var picture = PictureAdjustments()
            for _ in 0..<4 { picture.rotateClockwise() }
            t.expectEqual(picture.rotation, 0)
            picture.rotateClockwise()
            t.expectEqual(picture.rotation, 90)
        }
        t.test("zoom is mpv's power of two") {
            var picture = PictureAdjustments()
            t.expectEqual(picture.mpvZoom, 0)
            picture.zoom = 2
            t.expectEqual(picture.mpvZoom, 1)
        }
        t.test("values clamp to mpv's range") {
            t.expectEqual(PictureAdjustments.clamp(250), 100)
            t.expectEqual(PictureAdjustments.clamp(-250), -100)
        }
        t.test("every preset but Flat names a filter") {
            for preset in SoundPreset.allCases {
                t.expect((preset.lavfi == nil) == (preset == .flat), "\(preset.title)")
            }
        }
    }
}

@MainActor
func registerSubtitleMatcherTests(_ t: TestRunner) {
    t.suite("Subtitles for a whole season") { t in
        let subs = [
            "Show.S01E01.en.srt", "Show.S01E02.en.srt", "Show.S01E03.en.srt",
        ].map { URL(fileURLWithPath: "/subs/\($0)") }

        t.test("S01E02 pairs with S01E02, whatever else the names say") {
            let videos = [(id: "a", name: "Show.S01E02.1080p.WEB.x264-GRP.mkv"),
                          (id: "b", name: "Show.S01E01.Pilot.mkv")]
            let matched = SubtitleMatcher.match(videos: videos, subtitles: subs)
            t.expectEqual(matched["a"]?.lastPathComponent, "Show.S01E02.en.srt")
            t.expectEqual(matched["b"]?.lastPathComponent, "Show.S01E01.en.srt")
        }
        t.test("fansub numbering: the episode, not the resolution, the CRC or the year") {
            t.expectEqual(SubtitleMatcher.key(for: "[Group] Show 2019 - 07 [1080p][ABCD1234].mkv"), "e7")
            t.expectEqual(SubtitleMatcher.key(for: "Show - 07.ass"), "e7")
        }
        t.test("two subtitles for one episode are left for a person") {
            let two = [URL(fileURLWithPath: "/s/Show - 03 [EN].ass"), URL(fileURLWithPath: "/s/Show - 03 [ES].ass")]
            let matched = SubtitleMatcher.match(videos: [(id: "x", name: "Show - 03.mkv")], subtitles: two)
            t.expect(matched.isEmpty, "ambiguous stays unmatched")
        }
        t.test("a film's subtitle matches by name, language tag and all") {
            let matched = SubtitleMatcher.match(
                videos: [(id: "f", name: "The Film (1999).mkv")],
                subtitles: [URL(fileURLWithPath: "/s/The Film (1999).eng.srt")]
            )
            t.expectEqual(matched["f"]?.lastPathComponent, "The Film (1999).eng.srt")
        }
    }
}

@MainActor
func registerAccentThemeTests(_ t: TestRunner) {
    t.suite("Accent colour") { t in
        t.test("gold leaves every colour as it is") {
            UserDefaults.standard.removeObject(forKey: AccentTheme.storageKey)
            t.expectEqual(AccentTheme.map(0xC9A227), 0xC9A227)
            t.expectEqual(AccentTheme.map(0x123456), 0x123456)
        }
        t.test("another accent replaces only the accent family") {
            UserDefaults.standard.set(AccentTheme.blue.rawValue, forKey: AccentTheme.storageKey)
            defer { UserDefaults.standard.removeObject(forKey: AccentTheme.storageKey) }
            t.expectEqual(AccentTheme.map(0xC9A227), 0x3D9BFF)
            t.expectEqual(AccentTheme.map(0x8A6E12), 0x0A64C8)
            t.expectEqual(AccentTheme.map(0xF07B22), 0xF07B22)
        }
    }
}

@MainActor
func registerLocalUpNextTests(_ t: TestRunner) {
    func entry(_ id: String, played: Bool = false, position: Int64 = 0) -> LibraryEntry {
        let item = ItemRecord(id: id, serverId: LocalLibrary.serverId, type: "Video", name: id,
                              sortName: id, searchKey: id, isFolder: false, syncedAt: Date())
        var data = UserDataRecord(itemId: id, from: nil, updatedAt: Date())
        data.played = played
        data.playbackPositionTicks = position
        return LibraryEntry(item: item, userData: data)
    }

    t.suite("Up Next in a folder") { t in
        t.test("the file after the furthest one watched") {
            let next = LibraryRepository.nextUnwatched(in: [entry("1", played: true), entry("2"), entry("3", played: true), entry("4")])
            t.expectEqual(next?.id, "4")
        }
        t.test("nothing while one is half-watched — Continue has it") {
            t.expect(LibraryRepository.nextUnwatched(in: [entry("1", played: true), entry("2", position: 9_000_000_000)]) == nil,
                     "Continue covers it")
        }
        t.test("nothing once the folder is finished") {
            t.expect(LibraryRepository.nextUnwatched(in: [entry("1", played: true), entry("2", played: true)]) == nil, "done")
        }
    }
}
