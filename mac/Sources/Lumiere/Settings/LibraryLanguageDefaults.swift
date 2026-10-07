import SwiftUI
import LumiereKit

/// Per-library default audio and subtitle languages.
///
/// The setting that removes the most repeated work on an anime library: you already
/// know, before opening anything, that you want Japanese audio with English
/// subtitles. Without this the choice is remembered per *series*, which means making
/// it once for every show you ever start — hundreds of times to express one
/// preference.
///
/// A per-series choice still wins wherever one exists, because that is a decision
/// made about that particular show; this only fills the gap where none has been.
struct LibraryLanguageDefaults: View {
    let repository: LibraryRepository
    let libraries: [LibraryRecord]

    @State private var preferences: [String: TrackPreference] = [:]
    @State private var isLoading = true

    /// Codes rather than names, because that is what files carry. ISO 639-2/B is
    /// what Jellyfin reports most often, and the matcher already handles the
    /// two-letter forms and the spelled-out ones.
    private static let languages: [(code: String, name: String)] = [
        ("", "Server default"),
        ("jpn", "Japanese"),
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fre", "French"),
        ("ger", "German"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("kor", "Korean"),
        ("chi", "Chinese"),
        ("rus", "Russian"),
        ("ara", "Arabic"),
    ]

    /// The libraries this setting can mean anything for.
    ///
    /// A track preference is a choice between audio and subtitle streams, and three
    /// kinds of library have none to choose between: music has no subtitles,
    /// playlists and collections are lists of things that live in other libraries
    /// and inherit whatever those libraries were set to. Listing all eleven made a
    /// card long enough to scroll past, three rows of which could not do anything.
    ///
    /// Folder libraries — `3D`, `My Videos` — keep their rows. They have no
    /// collection type, but the files in them are ordinary video with ordinary
    /// tracks.
    private var applicable: [LibraryRecord] {
        libraries.filter { library in
            switch library.collectionType {
            case "music", "playlists", "boxsets", "photos", "musicvideos": return false
            default: return true
            }
        }
    }

    var body: some View {
        SettingsCard(
            title: "Default Languages",
            icon: "captions.bubble",
            subtitle: "Per library, when a series has no choice of its own"
        ) {
            AnimeLanguageToggle()
            if isLoading {
                ProgressView().controlSize(.small)
            } else if libraries.isEmpty {
                Text("No libraries yet.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            } else if applicable.isEmpty {
                Text("None of your libraries hold anything with audio or subtitle "
                   + "tracks to choose between.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The two pickers lost their inline labels when the rows collapsed
                // to one line; the columns are captioned once instead.
                HStack(spacing: Theme.Space.md) {
                    Color.clear.frame(width: 140, height: 1)
                    HStack(spacing: Theme.Space.sm) {
                        columnLabel("Audio")
                        columnLabel("Subtitles")
                    }
                    Spacer(minLength: 0)
                }
                ForEach(applicable) { library in
                    row(for: library)
                }
                Text("Applied when a series has no choice of its own. Picking audio "
                   + "or subtitles inside the player still overrides this for that "
                   + "show, and keeps overriding it.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await load() }
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .frame(maxWidth: 170, alignment: .leading)
    }

    private func row(for library: LibraryRecord) -> some View {
        let key = LibraryRepository.libraryTrackPreferenceKey(libraryId: library.id)
        let current = preferences[key]

        // One line each. The name above its pickers doubled the card's height for a
        // string short enough to sit beside them.
        return HStack(spacing: Theme.Space.md) {
            Text(library.name)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            HStack(spacing: Theme.Space.sm) {
                picker(
                    "Audio",
                    selection: current?.audioLanguage ?? "",
                    // Hopped back to the main actor: `picker` takes a @Sendable
                    // closure because that is what Binding's setter is, and `save`
                    // touches main-actor state.
                    onChange: { value in
                        Task { @MainActor in save(key: key, audio: value, subtitle: nil) }
                    }
                )
                picker(
                    "Subtitles",
                    selection: current?.subtitlesEnabled == false
                        ? "off" : (current?.subtitleLanguage ?? ""),
                    includesOff: true,
                    onChange: { value in
                        Task { @MainActor in save(key: key, audio: nil, subtitle: value) }
                    }
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func picker(
        _ label: String,
        selection: String,
        includesOff: Bool = false,
        // @Sendable because Binding's setter is, and passing a plain closure into
        // it is a warning the build gate treats as an error — rightly, since the
        // setter can be called from wherever SwiftUI happens to commit the change.
        onChange: @escaping @Sendable (String) -> Void
    ) -> some View {
        Picker(label, selection: Binding(get: { selection }, set: onChange)) {
            ForEach(Self.languages, id: \.code) { Text($0.name).tag($0.code) }
            if includesOff {
                Divider()
                Text("Off").tag("off")
            }
        }
        // Narrower now that the two sit on one line with the library's name.
        .frame(maxWidth: 170)
        .labelsHidden()
    }

    // MARK: - Storage

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var found: [String: TrackPreference] = [:]
        for library in applicable {
            let key = LibraryRepository.libraryTrackPreferenceKey(libraryId: library.id)
            if let preference = try? await repository.trackPreference(key: key) {
                found[key] = preference
            }
        }
        preferences = found
    }

    /// Writes one half of the pair while preserving the other, so choosing audio
    /// does not silently clear a subtitle language set a moment earlier.
    private func save(key: String, audio: String?, subtitle: String?) {
        let existing = preferences[key]
        var updated = TrackPreference(
            key: key,
            audioLanguage: existing?.audioLanguage,
            subtitleLanguage: existing?.subtitleLanguage,
            subtitlesEnabled: existing?.subtitlesEnabled ?? true
        )

        if let audio {
            updated.audioLanguage = audio.isEmpty ? nil : audio
        }
        if let subtitle {
            // "Off" is a real choice and has to stay distinguishable from "never
            // picked anything" — the same distinction the per-series memory makes.
            updated.subtitlesEnabled = subtitle != "off"
            updated.subtitleLanguage = (subtitle.isEmpty || subtitle == "off") ? nil : subtitle
        }

        preferences[key] = updated
        Task { try? await repository.saveTrackPreference(updated) }
    }
}

/// Whether anime starts in Japanese with English subtitles when nothing is set.
struct AnimeLanguageToggle: View {
    @AppStorage(Preference.animeDefaultsToJapanese.name) private var on
        = Preference.animeDefaultsToJapanese.defaultValue

    var body: some View {
        Toggle("Anime in Japanese with English subtitles", isOn: $on)
        SettingsNote("For libraries named for anime, when neither the show nor the library has a "
                   + "choice below. Dialogue subtitles are preferred over signs-and-songs tracks.")
    }
}
