import SwiftUI
import LumiereKit

extension SeasonEpisodeList {

    /// Ask TMDB for the episode pictures this show is missing.
    ///
    /// Beside "Fix from Filenames…" because it is the same kind of act: a repair
    /// someone runs on a show that came out of a scan incomplete. Only ever adds
    /// — the server offers the episodes with no picture and refuses the rest, so
    /// a still Jellyfin scraped or a frame grabbed from the file is never
    /// replaced.
    @ViewBuilder
    var fetchStillsButton: some View {
        Button {
            Task { await model.fetchEpisodeImages() }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if model.isFetchingEpisodeImages {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "photo.badge.arrow.down").font(Theme.Font.badge)
                }
                Text(model.isFetchingEpisodeImages ? "Fetching…" : "Get Artwork from TMDB")
            }
            .font(Theme.Font.cardTitle)
            .foregroundStyle(
                isHoveringStills ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
            )
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(
                isHoveringStills ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                in: Capsule()
            )
            .overlay { Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(model.isFetchingEpisodeImages)
        .labelledHelp("Fill in missing episode pictures from TMDB. Episodes that already "
            + "have one are left alone.")
        .onHover { isHoveringStills = $0 }
        .animation(Theme.Motion.hover, value: isHoveringStills)
    }
}
