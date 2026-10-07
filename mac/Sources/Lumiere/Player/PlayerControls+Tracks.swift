import SwiftUI
import LumiereKit

extension PlayerControls {

    /// What is playing, as a label you can read without opening anything.
    ///
    /// `Japanese · English` beats a captions icon: it answers the question
    /// people actually have — am I on the dub — and it is still the button that
    /// opens the track panel, so nothing was traded away for it.
    ///
    /// Falls back to the icon alone where a file has one audio track and no
    /// subtitles, which is most films: there is no choice to report, and a label
    /// saying so would be noise on every one of them.
    var trackSummaryButton: some View {
        Button {
            showsQueue = false
            openTab = openTab == nil ? .audio : nil
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: Theme.PlayerMetric.secondaryGlyph, weight: .medium))
                if let summary = trackSummary {
                    Text(summary)
                        .font(Theme.Font.cardTitle)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(openTab != nil
                             ? Theme.PlayerPalette.primaryGlyph
                             : Theme.Palette.onPlayerChromeSecondary)
            .padding(.horizontal, trackSummary == nil ? 0 : Theme.Space.xs)
            .frame(height: Theme.PlayerMetric.secondaryButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .labelledHelp("Audio, subtitles, speed and chapters")
    }

    /// `Japanese · English`, `Japanese · no subtitles`, or nil where there is
    /// nothing to choose between.
    private var trackSummary: String? {
        let hasChoice = model.audioTracks.count > 1 || !model.subtitleTracks.isEmpty
        guard hasChoice else { return nil }

        let audio = model.audioTracks
            .first { $0.id == model.selectedAudioTrack }?
            .language.flatMap(DetailAbout.languageName) ?? "Audio"

        guard let subtitleId = model.selectedSubtitleTrack else {
            return "\(audio) · no subtitles"
        }
        let subtitle = model.subtitleTracks
            .first { $0.id == subtitleId }?
            .language.flatMap(DetailAbout.languageName) ?? "on"
        return "\(audio) · \(subtitle)"
    }
}
