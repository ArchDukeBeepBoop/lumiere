import Foundation
import TestKit
import LumiereKit

/// Track memory is matched by language, never by index, and these pin why.
@MainActor
func registerTrackPreferenceTests(_ t: TestRunner) {

    /// A stand-in for MediaTrack, which lives in LumierePlayer.
    struct Track: TrackDescribing {
        let id: Int
        let language: String?
        let isDefault: Bool
    }

    t.suite("Track preferences") { t in

        t.test("the remembered language wins over the file's own default") {
            // The whole feature: episode 2 numbers Japanese differently from episode 1,
            // and a remembered index would quietly start playing the dub.
            let tracks = [
                Track(id: 1, language: "eng", isDefault: true),
                Track(id: 2, language: "jpn", isDefault: false),
            ]
            t.expectEqual(TrackPreference.match(language: "jpn", in: tracks), 2)
        }

        t.test("the same language at a different index still resolves") {
            let episodeOne = [
                Track(id: 1, language: "eng", isDefault: true),
                Track(id: 2, language: "jpn", isDefault: false),
            ]
            let episodeTwo = [
                Track(id: 1, language: "jpn", isDefault: false),
                Track(id: 2, language: "eng", isDefault: true),
            ]
            t.expectEqual(TrackPreference.match(language: "jpn", in: episodeOne), 2)
            t.expectEqual(TrackPreference.match(language: "jpn", in: episodeTwo), 1)
        }

        t.test("language codes match across the forms servers report") {
            // The same track is "jpn", "ja" or "ja-JP" depending on the file.
            let tracks = [Track(id: 7, language: "ja", isDefault: false)]
            t.expectEqual(TrackPreference.match(language: "jpn", in: tracks), 7)
            t.expectEqual(TrackPreference.match(language: "ja-JP", in: tracks), 7)
        }

        t.test("case does not matter") {
            let tracks = [Track(id: 3, language: "JPN", isDefault: false)]
            t.expectEqual(TrackPreference.match(language: "jpn", in: tracks), 3)
        }

        t.test("a language the file lacks falls back to its default, not to track one") {
            // A release with commentary first would otherwise open on the commentary.
            let tracks = [
                Track(id: 1, language: "com", isDefault: false),
                Track(id: 2, language: "eng", isDefault: true),
            ]
            t.expectEqual(TrackPreference.match(language: "fre", in: tracks), 2)
        }

        t.test("no remembered language means the file's default") {
            let tracks = [
                Track(id: 1, language: "eng", isDefault: false),
                Track(id: 2, language: "jpn", isDefault: true),
            ]
            t.expectEqual(TrackPreference.match(language: nil, in: tracks), 2)
        }

        t.test("no tracks at all is nil rather than a crash") {
            t.expect(TrackPreference.match(language: "jpn", in: [Track]()) == nil)
        }

        t.test("subtitles off is remembered as a choice, not as absence") {
            // Without the flag, "I turned subtitles off" is indistinguishable from
            // "I never picked any", and they must behave differently.
            let off = TrackPreference(key: "s1", subtitlesEnabled: false)
            let never = TrackPreference(key: "s2")
            t.expect(!off.subtitlesEnabled)
            t.expect(never.subtitlesEnabled)
        }
    }
}
