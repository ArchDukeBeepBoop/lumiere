import SwiftUI
import LumiereKit

/// The languages a title will play in, as two glass chips under Play —
/// "Japanese" and "English subtitles" — that open the same two-column menu
/// the player has. A choice here is the series' remembered choice, so the
/// player starts in it.
struct LanguageChips: View {
    let repository: LibraryRepository
    /// The series for an episode, the film itself otherwise. See
    /// `LibraryRepository.trackPreferenceKey`.
    let key: String
    let streams: [MediaStream]

    @State private var preference: TrackPreference?
    @State private var isOpen = false

    private var audio: [String] { unique(streams.filter { $0.type == .audio }) }
    private var subtitles: [String] { unique(streams.filter { $0.type == .subtitle }) }

    var body: some View {
        if !audio.isEmpty {
            Button { isOpen.toggle() } label: {
                HStack(spacing: Theme.Space.xs) {
                    chip("speaker.wave.2", name(preference?.audioLanguage ?? defaultAudio))
                    chip("captions.bubble", subtitleLabel)
                }
            }
            .buttonStyle(.plain)
            .labelledHelp("Audio and subtitles for this title")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) { menu }
            .task(id: key) { preference = try? await repository.trackPreference(key: key) }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(Theme.Glyph.sm(.semibold))
            Text(text).font(Theme.Font.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.sm + 2)
        .padding(.vertical, 5)
        .background { GlassFill(shape: Capsule()) }
        .overlay { Capsule().strokeBorder(Theme.Palette.border.opacity(0.6), lineWidth: 1) }
    }

    private var menu: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            column("Language") {
                ForEach(audio, id: \.self) { code in
                    PlayerPanelRow(title: name(code), detail: nil,
                                   selected: (preference?.audioLanguage ?? defaultAudio) == code) {
                        save { $0.audioLanguage = code }
                    }
                }
            }
            Rectangle().fill(Theme.PlayerPalette.surfaceStroke).frame(width: 1)
            column("Subtitles") {
                PlayerPanelRow(title: "Off", detail: nil, selected: preference?.subtitlesEnabled == false) {
                    save { $0.subtitlesEnabled = false }
                }
                ForEach(subtitles, id: \.self) { code in
                    PlayerPanelRow(title: name(code), detail: nil,
                                   selected: preference?.subtitlesEnabled != false && preference?.subtitleLanguage == code) {
                        save { $0.subtitlesEnabled = true; $0.subtitleLanguage = code }
                    }
                }
            }
        }
        .padding(Theme.Space.sm)
        .frame(width: 420)
        .environment(\.colorScheme, .dark)
        .background(Theme.PlayerPalette.glassTint)
    }

    private func column<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PlayerSectionLabel(title)
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var defaultAudio: String? {
        streams.first { $0.type == .audio && $0.isDefault == true }?.language
            ?? streams.first { $0.type == .audio }?.language
    }

    private var subtitleLabel: String {
        guard let preference else { return "Subtitles as the file chooses" }
        guard preference.subtitlesEnabled, let code = preference.subtitleLanguage else { return "No subtitles" }
        return "\(name(code)) subtitles"
    }

    private func name(_ code: String?) -> String {
        DetailAbout.languageName(code) ?? code?.uppercased() ?? "Original"
    }

    private func unique(_ list: [MediaStream]) -> [String] {
        var seen = Set<String>()
        return list.compactMap(\.language).filter { seen.insert($0).inserted }
    }

    private func save(_ change: (inout TrackPreference) -> Void) {
        var next = preference ?? TrackPreference(key: key)
        change(&next)
        next.updatedAt = Date()
        preference = next
        let value = next
        Task { try? await repository.saveTrackPreference(value) }
    }
}
