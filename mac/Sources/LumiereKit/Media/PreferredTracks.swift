import Foundation

/// Which tracks a session should start on, chosen from the server's own stream
/// list rather than from an engine's.
///
/// It has to be answerable *before* playback starts, and that is the whole reason
/// this exists. `PlayerModel.applyRememberedTracks` picks tracks after the engine
/// has loaded and reports them — which is the right mechanism for a direct play,
/// where switching a track is a local operation. It is useless for a transcode:
/// the server bakes one audio track and one burned-in subtitle into the stream, so
/// the choice has to travel in the URL that starts it.
///
/// Without this, `audioStreamIndex` and `subtitleStreamIndex` were never sent —
/// measured across a full traffic capture, not one request carried either — so a
/// transcode always got the server's defaults, and burned-in subtitles could not be
/// asked for at all.
///
/// Pure, and keyed on Jellyfin's own `Index`, which is exactly what the URL wants.
public enum PreferredTracks {

    /// The indices to start on. Nil means "say nothing and take the default",
    /// which is different from an explicit choice and must stay different.
    public struct Choice: Sendable, Equatable {
        public let audioIndex: Int?
        public let subtitleIndex: Int?

        public init(audioIndex: Int?, subtitleIndex: Int?) {
            self.audioIndex = audioIndex
            self.subtitleIndex = subtitleIndex
        }
    }

    /// A `MediaStream` seen as a track the preference matcher can reason about.
    ///
    /// An adapter rather than a conformance on `MediaStream` itself: the protocol
    /// wants a non-optional `title`, `isDefault` and `isForced`, and the model
    /// carries all three as optionals under the same names. Bridging them here
    /// keeps the model honest about what the server actually sent.
    private struct StreamTrack: SubtitleTrackDescribing {
        let stream: MediaStream
        var id: Int { stream.index }
        var language: String? { stream.language }
        var isDefault: Bool { stream.isDefault ?? false }
        var isForced: Bool { stream.isForced ?? false }
        var title: String { stream.displayTitle ?? stream.title ?? "" }
    }

    public static func resolve(
        source: MediaSource,
        preference: TrackPreference?,
        subtitleKind: SubtitleKind
    ) -> Choice {
        let audio = source.audioStreams.map(StreamTrack.init)
        let subtitles = source.subtitleStreams.map(StreamTrack.init)

        // No stored preference means no opinion: the server's own defaults are as
        // good an answer as any, and sending an index we invented would override a
        // correct default with a guess.
        guard let preference else {
            // Except for a subtitle fetched on purpose: one this server
            // downloaded from OpenSubtitles in the language searched for.
            // Queuing a season's subtitles and then having each episode open
            // with them off is the queue doing half its job.
            return Choice(audioIndex: nil, subtitleIndex: fetchedSubtitle(
                in: source.subtitleStreams, language: Preference.subtitleSearchLanguage.value))
        }

        let audioIndex = TrackPreference.match(
            language: preference.audioLanguage, in: audio
        )

        // "Off" is a choice, and a stored one. See `TrackPreference.subtitlesEnabled`.
        let subtitleIndex = preference.subtitlesEnabled
            ? TrackPreference.matchSubtitle(
                language: preference.subtitleLanguage,
                preferring: subtitleKind,
                in: subtitles
              )
            : nil

        return Choice(audioIndex: audioIndex, subtitleIndex: subtitleIndex)
    }

    /// A subtitle the server fetched from the provider in `language`, if any.
    /// Pure: the language is passed in so it can be tested.
    public static func fetchedSubtitle(in streams: [MediaStream], language: String) -> Int? {
        let wanted = language.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "en"
        return streams.first { stream in
            guard stream.isExternal == true,
                  (stream.title ?? stream.displayTitle ?? "").contains("OpenSubtitles"),
                  let value = stream.language?.lowercased(), !wanted.isEmpty
            else { return false }
            return value.hasPrefix(String(wanted.prefix(2))) || wanted.hasPrefix(String(value.prefix(2)))
        }?.index
    }
}
