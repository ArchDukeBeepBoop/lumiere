import Foundation
import TestKit
import LumiereKit

/// Which tracks a session starts on, chosen before an engine exists.
///
/// The reason this is pinned: for a transcode the choice travels in the URL, and
/// a full traffic capture showed neither `audioStreamIndex` nor
/// `subtitleStreamIndex` ever being sent. Every case here is about the two ways
/// that can silently go wrong again — sending nothing, or sending the wrong number.
@MainActor
func registerPreferredTracksTests(_ t: TestRunner) {

    t.suite("Preferred tracks") { t in

        t.test("no stored preference says nothing, rather than guessing") {
            // Important that this is nil and not "the first track": an invented
            // index overrides the server's own default with a guess.
            let choice = PreferredTracks.resolve(
                source: source(), preference: nil, subtitleKind: .dialogue
            )
            t.expectNil(choice.audioIndex)
            t.expectNil(choice.subtitleIndex)
        }

        t.test("the index sent is the server's, not the position in the list") {
            // The whole point. Audio streams here are at Jellyfin indices 2 and 4
            // while sitting at array positions 0 and 1, and a URL built from the
            // position plays the wrong language — or nothing.
            let choice = PreferredTracks.resolve(
                source: source(),
                preference: TrackPreference(
                    key: "k", audioLanguage: "jpn",
                    subtitleLanguage: "eng", subtitlesEnabled: true
                ),
                subtitleKind: .dialogue
            )
            t.expectEqual(choice.audioIndex, 4)
        }

        t.test("subtitles turned off send no index even when one matches") {
            let choice = PreferredTracks.resolve(
                source: source(),
                preference: TrackPreference(
                    key: "k", audioLanguage: "eng",
                    subtitleLanguage: "eng", subtitlesEnabled: false
                ),
                subtitleKind: .dialogue
            )
            t.expectEqual(choice.audioIndex, 2)
            t.expectNil(choice.subtitleIndex)
        }

        t.test("a dialogue preference skips the signs-and-songs track") {
            // Both are English. Picking the first leaves subtitles on with none of
            // the speech subtitled, which is the bug `SubtitleKind` exists for.
            let choice = PreferredTracks.resolve(
                source: source(),
                preference: TrackPreference(
                    key: "k", audioLanguage: "jpn",
                    subtitleLanguage: "eng", subtitlesEnabled: true
                ),
                subtitleKind: .dialogue
            )
            t.expectEqual(choice.subtitleIndex, 6)
        }
    }
}

/// Streams numbered the way a real file is: video 0, audio 2 and 4, subtitles 5
/// and 6 — deliberately not 0, 1, 2, 3 in array order.
@MainActor
private func source() -> MediaSource {
    let streams: [[String: Any]] = [
        ["Index": 0, "Type": "Video", "Codec": "h264"],
        ["Index": 2, "Type": "Audio", "Codec": "aac", "Language": "eng", "IsDefault": true],
        ["Index": 4, "Type": "Audio", "Codec": "flac", "Language": "jpn"],
        ["Index": 5, "Type": "Subtitle", "Codec": "ass", "Language": "eng",
         "Title": "Signs & Songs", "DisplayTitle": "English [Signs & Songs]"],
        ["Index": 6, "Type": "Subtitle", "Codec": "ass", "Language": "eng",
         "Title": "Dialogue", "DisplayTitle": "English [Dialogue]"],
    ]
    let json: [String: Any] = [
        "Id": "src", "Container": "mkv", "MediaStreams": streams,
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JellyfinClient.decoder.decode(MediaSource.self, from: data)
}
