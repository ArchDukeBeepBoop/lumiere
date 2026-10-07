import SwiftUI
import LumiereKit

/// One cell in the episode strip: still frame, unwatched corner, number, title and
/// duration.
///
/// Split from SeasonEpisodeList.swift for the project's 300-line limit.
///
/// What it says, and what it deliberately does not: the TV app's episode row shows
/// number, title, duration, watched state and a synopsis. The first four are here.
/// The synopsis is not, because this strip is horizontal and the hero directly
/// above it is already showing the selected episode's own synopsis in full — the
/// whole reason selecting a cell does not navigate anywhere. Repeating two clamped
/// lines of it in every tile would be the same text twice at a worse size.
struct EpisodeThumbnail: View {
    let entry: LibraryEntry
    let isSelected: Bool
    let pipeline: ImagePipeline
    let serverURL: URL
    let scale: CGFloat
    let onSelect: () -> Void
    /// Plays this episode outright. The disc on the artwork is this; the rest of the
    /// tile still selects.
    var onPlay: (() -> Void)?

    @State private var isHovering = false
    @AppStorage("showsUnwatchedBadges") private var showsUnwatchedBadges = true
    /// Off by default. See `ImageRequest.backdrop`.
    @AppStorage("unifiedEpisodeArt") private var unifiedEpisodeArt = false

    /// 360 — the memory arithmetic, and the reasoning against the rest of the
    /// page, are in `DetailMetrics.episodeWidth`.
    ///
    /// The note that first stood here argued for staying small because an anime
    /// season runs to a hundred episodes and every extra 40pt is one fewer tile on
    /// screen. That treats the strip as a list to get through; the TV app treats
    /// it as artwork to look at, and at 200pt a still was too small to tell two
    /// similar scenes apart, which is a still's only job. Nothing about the
    /// strip's behaviour changes: every episode of the selected season, eager,
    /// scrolled to the hero on appear — with chevrons over it now, saying that
    /// there are more of them past the right edge.
    private let width = DetailMetrics.episodeWidth

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                still
                labels
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
    }

    private var still: some View {
        RemoteImage(
            request: .backdrop(
                for: entry, serverURL: serverURL, width: width, scale: scale,
                unifiesEpisodeArt: unifiedEpisodeArt
            ),
            pipeline: pipeline
        )
        .frame(width: width, height: width / Theme.Art.thumbAspect)
        .overlay(alignment: .bottom) { progressBar }
        .overlay(alignment: .topTrailing) { unwatchedBadge }
        .overlay(alignment: .center) { playAffordance }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.posterLarge, style: .continuous))
        // The selection ring stays a ring — it is state, not a cursor, and it has
        // to be legible on the tile you are *not* pointing at. Hover became the
        // lift the rest of the app uses: a border on hover as well made every cell
        // look selected as the pointer crossed the strip.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.posterLarge, style: .continuous)
                .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: 2)
        }
        // Radius zero when idle, not merely a clear colour. A shadow left in the
        // tree at full radius gives every cell an offscreen buffer whether or not
        // anything is drawn into it, and a merged anime series puts a hundred of
        // these in one strip.
        .shadow(
            color: isHovering ? Theme.Palette.cardShadow : .clear,
            radius: isHovering ? Theme.Elevation.hoverShadow : 0,
            y: isHovering ? Theme.Elevation.hoverShadowY : 0
        )
        .scaleEffect(isHovering ? Theme.Elevation.hoverScale : 1)
    }

    /// Number and title on one line, duration and watched state under it — the
    /// shape the TV app uses, and the reason is that "which episode is this?" is
    /// answered by the number far more often than by the title, especially on a
    /// show whose episodes are all called some variation of the same thing.
    ///
    /// The number is now its own run of type rather than a `"4. "` prefix inside
    /// the title string. Set in the same weight and colour as the title it was
    /// glued to, it scanned as part of the sentence; separated and set bold, a
    /// column of them down the strip is a thing the eye can run along — which is
    /// the whole argument for putting the number first in the first place. It also
    /// stops a long title eating the number when the line truncates, which the
    /// single-string version did from the wrong end.
    private var labels: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                if let number = entry.item.indexNumber {
                    Text("\(number)")
                        .font(Theme.Font.cardTitleLarge.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(
                            isSelected ? Theme.Palette.accent : Theme.Palette.textMuted
                        )
                }
                // No number for a specials folder or a mis-scraped season, and
                // inventing one would be a lie — the title simply takes the line.
                Text(entry.item.name)
                    .font(Theme.Font.cardTitleLarge)
                    .foregroundStyle(
                        isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: Theme.Space.xs) {
                if entry.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Theme.Font.captionLarge)
                        .foregroundStyle(Theme.Palette.accent)
                }
                if let runtime = runtimeText {
                    Text(runtime)
                        .font(Theme.Font.captionLarge)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
            // Reserved whether or not anything is in it, so the cells' still frames
            // stay on one baseline. An episode with no cached runtime otherwise
            // pulls its whole tile up by a line and the strip goes ragged. Grown
            // with the type on it — at 14 a 12pt line was clipped at the descender.
            .frame(height: 17, alignment: .leading)
        }
    }

    private var runtimeText: String? {
        guard let seconds = entry.item.runtimeSeconds, seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Only under the cursor, matching the wide cards on Home — and it plays.
    ///
    /// It used to be a `chevron.up` that did nothing: a disc drawn on the artwork to
    /// hint that the tile was "live", while a click anywhere on the tile swapped the
    /// hero. A circular button on a piece of artwork is read as Play by everyone who
    /// has used any other media app, so it is Play now. The rest of the tile still
    /// selects, which is what the tile is for.
    @ViewBuilder
    private var playAffordance: some View {
        if isHovering, let onPlay {
            Button(action: onPlay) {
                // Scaled with the tile, the same way `WideCard` scales its play
                // disc: a 36pt circle centred on a 300pt still reads as a speck.
                Circle()
                    .fill(Theme.Palette.onArtworkStrong)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Palette.onPlayerChrome)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .labelledHelp("Play this episode")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var unwatchedBadge: some View {
        if showsUnwatchedBadges, entry.showsUnwatchedMarker {
            // 30, as `PosterCard` uses on a large tile. The corner has to stay the
            // same fraction of the artwork to keep reading as a folded corner.
            UnwatchedCorner()
                .fill(Theme.Palette.unwatched)
                .frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress = entry.progress {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Palette.onArtwork)
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)
        }
    }
}
