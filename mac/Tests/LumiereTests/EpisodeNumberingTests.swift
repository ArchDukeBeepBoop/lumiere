import Foundation
import TestKit
import LumiereKit

/// Recovering season and episode numbers the server misread.
@MainActor
func registerEpisodeNumberingTests(_ t: TestRunner) {

    t.suite("Episode numbering") { t in

        t.test("the real filename that lost an episode parses correctly") {
            // Jellyfin read "Fireteam E601" and returned episode 601 of no season,
            // so the first episode of the show never appeared in its own list.
            let parsed = EpisodeNumbering.parse(
                path: "/Anime/Sky Wizards Academy/Sky Wizards Academy - 1x01 - Fireteam E601.mkv"
            )
            t.expectEqual(parsed, .init(season: 1, episode: 1))
        }

        t.test("SxxExx is read") {
            t.expectEqual(EpisodeNumbering.parse(name: "Show - S02E07.mkv"),
                          .init(season: 2, episode: 7))
            t.expectEqual(EpisodeNumbering.parse(name: "show.s1e2.1080p.mkv"),
                          .init(season: 1, episode: 2))
        }

        t.test("a resolution is never mistaken for a numbering") {
            // "1920x1080" is the most common number in a fansub filename, and
            // reading it as season 1920 would be worse than reading nothing.
            t.expectNil(EpisodeNumbering.parse(name: "[Doki] Show (1920x1080 Hi10P).mkv"))
        }

        t.test("the first marker wins, not the last number") {
            // The whole bug: a number inside the episode's own title must never
            // outrank the structural marker that came before it.
            t.expectEqual(EpisodeNumbering.parse(name: "Show - 1x03 - Unit 88 Deploys.mkv"),
                          .init(season: 1, episode: 3))
        }

        t.test("a name with no marker yields nothing") {
            t.expectNil(EpisodeNumbering.parse(name: "Some Movie (2011).mkv"))
            t.expectNil(EpisodeNumbering.parse(path: nil))
        }

        t.test("only the filename is read, never the folders above it") {
            // A Specials folder under Season 1/ must not inherit season 1.
            t.expectNil(EpisodeNumbering.parse(path: "/Anime/Show/Season 1/Extra.mkv"))
        }
    }
}

/// Telling an English dialogue track from an English signs-and-songs one.
@MainActor
func registerSubtitleKindTests(_ t: TestRunner) {

    struct Track: SubtitleTrackDescribing {
        let id: Int
        let title: String
        let language: String?
        let isDefault: Bool
        let isForced: Bool
    }

    t.suite("Subtitle kinds") { t in

        t.test("the common labels are recognised") {
            t.expectEqual(SubtitleKind.classify(title: "English (Signs & Songs)"), .signsAndSongs)
            t.expectEqual(SubtitleKind.classify(title: "English SDH"), .sdh)
            t.expectEqual(SubtitleKind.classify(title: "English CC"), .closedCaptions)
            t.expectEqual(SubtitleKind.classify(title: "English Dialogue"), .dialogue)
            t.expectEqual(SubtitleKind.classify(title: "S&S"), .signsAndSongs)
        }

        t.test("a word containing signs is not a signs track") {
            // "designs" contains "signs"; substring matching would hide the speech.
            t.expectEqual(SubtitleKind.classify(title: "Costume Designs Commentary"), .other)
        }

        t.test("an unlabelled track is dialogue") {
            // By far the common case: one ordinary stream with nothing written on
            // it. Guessing anything else would break the majority to serve an edge.
            t.expectEqual(SubtitleKind.classify(title: nil), .dialogue)
            t.expectEqual(SubtitleKind.classify(title: "[HorribleSubs]"), .dialogue)
        }

        t.test("an unlabelled forced track is signs") {
            t.expectEqual(SubtitleKind.classify(title: nil, isForced: true), .signsAndSongs)
        }

        t.test("the hearing-impaired flag beats the title") {
            t.expectEqual(
                SubtitleKind.classify(title: "English", isHearingImpaired: true), .sdh
            )
        }

        t.test("dialogue is chosen over signs, whatever the track order") {
            let tracks = [
                Track(id: 0, title: "English (Signs & Songs)", language: "eng",
                      isDefault: true, isForced: false),
                Track(id: 1, title: "English", language: "eng",
                      isDefault: false, isForced: false),
            ]
            // Track 0 is first *and* default — a language-only match takes it, and
            // that is exactly the case that looks like a broken player.
            t.expectEqual(
                TrackPreference.matchSubtitle(
                    language: "eng", preferring: .dialogue, in: tracks
                ), 1
            )
        }

        t.test("asking for dialogue falls back to CC before signs") {
            let tracks = [
                Track(id: 0, title: "English (Signs & Songs)", language: "eng",
                      isDefault: false, isForced: false),
                Track(id: 1, title: "English CC", language: "eng",
                      isDefault: false, isForced: false),
            ]
            t.expectEqual(
                TrackPreference.matchSubtitle(
                    language: "eng", preferring: .dialogue, in: tracks
                ), 1
            )
        }

        t.test("someone who asks for signs gets signs") {
            let tracks = [
                Track(id: 0, title: "English", language: "eng",
                      isDefault: true, isForced: false),
                Track(id: 1, title: "Signs & Songs", language: "eng",
                      isDefault: false, isForced: false),
            ]
            t.expectEqual(
                TrackPreference.matchSubtitle(
                    language: "eng", preferring: .signsAndSongs, in: tracks
                ), 1
            )
        }

        t.test("the requested language still wins over the requested kind") {
            let tracks = [
                Track(id: 0, title: "English", language: "eng",
                      isDefault: true, isForced: false),
                Track(id: 1, title: "Español (Signs)", language: "spa",
                      isDefault: false, isForced: false),
            ]
            t.expectEqual(
                TrackPreference.matchSubtitle(
                    language: "spa", preferring: .dialogue, in: tracks
                ), 1
            )
        }

        t.test("no tracks means no choice, not a crash") {
            t.expectNil(
                TrackPreference.matchSubtitle(
                    language: "eng", preferring: .dialogue, in: [Track]()
                )
            )
        }
    }
}
