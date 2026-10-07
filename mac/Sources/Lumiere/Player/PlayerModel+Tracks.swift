import Foundation
import LumiereKit
import LumierePlayer

/// Remembering which audio and subtitle track this show is watched with.
///
/// Split from PlayerModel+Controls.swift for the project's 300-line limit, and the
/// seam is a real one: everything here is about a *stored* choice rather than a
/// live one. Nothing is private — PlayerModel+Session.swift reads the preference
/// before playback starts, because a transcode has to bake the choice into its URL.
/// See `PreferredTracks`.
extension PlayerModel {

    /// Dialogue by default, because that is what "turn on subtitles" means to
    /// nearly everyone. Someone watching a dub wants signs-and-songs and can say so
    /// once rather than re-picking a track every episode.
    var preferredSubtitleKind: SubtitleKind {
        SubtitleKind(rawValue: UserDefaults.standard.string(forKey: "preferredSubtitleKind") ?? "")
            ?? .dialogue
    }

    /// The stored choice for this item: the show's own first, then the library's.
    ///
    /// One lookup rather than two copies of the order. A decision made about this
    /// specific series must not be overridden by a blanket setting — but where no
    /// such decision exists, "everything in Anime is Japanese audio with English
    /// subtitles" is exactly the right answer.
    ///
    /// Not private: PlayerModel+Session.swift needs it *before* playback starts, to
    /// put the indices in a transcode URL. See `PreferredTracks`.
    func rememberedPreference() async -> TrackPreference? {
        if let key = preferenceKey,
           let preference = try? await repository.trackPreference(key: key) {
            return preference
        }
        if let libraryKey = libraryPreferenceKey,
           let preference = try? await repository.trackPreference(key: libraryKey) {
            return preference
        }
        // Nothing chosen for the show or the library, and the library is anime:
        // Japanese audio, English subtitles for the dialogue — what nearly
        // everyone watching it wants from the first episode, rather than the
        // English dub a release lists first. A choice made anywhere wins.
        if Preference.animeDefaultsToJapanese.value, await isInAnimeLibrary() {
            return TrackPreference(key: "anime-default", audioLanguage: "jpn",
                                   subtitleLanguage: "eng", subtitlesEnabled: true)
        }
        return nil
    }

    private func isInAnimeLibrary() async -> Bool {
        guard let libraryId = (try? await repository.entry(id: itemId))?.item.libraryId else { return false }
        let libraries = (try? await repository.libraries()) ?? []
        return libraries.first { $0.id == libraryId }.map { LibraryKinds.isAnime($0.name) } ?? false
    }

    func applyRememberedTracks() async {
        // The show's own choice first, then the library's default. A decision made
        // about this specific series must not be overridden by a blanket setting —
        // but where no such decision exists, "everything in Anime is Japanese audio
        // with English subtitles" is exactly the right answer.
        guard let preference = await rememberedPreference() else { return }

        if let audio = TrackPreference.match(language: preference.audioLanguage, in: audioTracks),
           audio != selectedAudioTrack {
            selectedAudioTrack = audio
            await engineRef?.selectAudioTrack(id: audio)
        }

        if preference.subtitlesEnabled {
            // Dialogue by preference, which is the whole point: a release's first
            // English track is very often signs-and-songs, and choosing it leaves
            // subtitles on with none of the speech subtitled.
            if let subtitle = TrackPreference.matchSubtitle(
                language: preference.subtitleLanguage,
                preferring: preferredSubtitleKind,
                in: subtitleTracks
            ), subtitle != selectedSubtitleTrack {
                selectedSubtitleTrack = subtitle
                await engineRef?.selectSubtitleTrack(id: subtitle)
            }
        } else if selectedSubtitleTrack != nil {
            selectedSubtitleTrack = nil
            await engineRef?.selectSubtitleTrack(id: nil)
        }
    }
}
