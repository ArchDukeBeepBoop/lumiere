import SwiftUI
import LumiereKit

/// A genre, as a piece of artwork you can click.
///
/// Jellyfin reaches genres through a sidebar list of words, which is a filing
/// cabinet: you have to already know what you want before the UI helps. Apple TV
/// treats a category as a destination with a picture on it, and that is what this
/// is — the genre's own titles supply the artwork, the genre supplies the name,
/// and the count says how much is behind it.
///
/// A mosaic of up to three posters rather than one still, which is the fix for
/// the complaint that genres all looked alike. One still meant the card showed
/// the newest title in the genre — and on a library organised the way most are,
/// the newest thing in Action is also the newest thing in Adventure and Thriller,
/// so three cards in the same row carried the same picture, often a picture
/// already on a shelf twenty points below.
///
/// It costs less than the single image it replaces, not more. Three slices a
/// third of the card wide decode roughly a third of the pixels each, so the card
/// totals slightly under one full-width backdrop — the opposite of the usual
/// mosaic trade, and the reason the row can now afford eighteen cards. The old
/// comment here warned against "four decoded bitmaps times ten cards"; that
/// warning was about four *full-size* tiles, which this is not.
struct GenreCard: View {
    let genre: GenreCardItem
    let serverURL: URL
    let pipeline: ImagePipeline
    var width: CGFloat = Theme.Art.genreCardWidth

    @State private var isHovering = false
    @Environment(\.displayScale) private var scale

    private var height: CGFloat { width / Theme.Art.backdropAspect }

    /// A hairline, so the mosaic reads as several pictures rather than one wide
    /// one.
    private let seam: CGFloat = 1

    /// The titles this card can actually draw, newest first and deduplicated.
    ///
    /// Filtered on whether artwork exists rather than taken blindly, because a
    /// genre whose newest title has not been scraped yet would otherwise get a
    /// blank slice — which looks like a loading failure, not like a design.
    private var drawable: [LibraryEntry] {
        var seen = Set<String>()
        return genre.artwork.filter { entry in
            guard seen.insert(entry.id).inserted else { return false }
            return ImageRequest.poster(
                for: entry, serverURL: serverURL, width: width, scale: scale
            ) != nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            // Over the artwork and under the label. The wash is what keeps two
            // genres apart when they happen to share their titles' artwork, and
            // it is the only part of the card that still works at zero posters.
            tint
            label
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.posterLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.posterLarge, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
        // The same lift every other card in the app takes, at the same numbers,
        // and with the shadow radius at zero when idle — a shadow left installed
        // at full radius gives every repeated tile an offscreen buffer.
        .shadow(
            color: isHovering ? Theme.Palette.cardShadow : .clear,
            radius: isHovering ? Theme.Elevation.hoverShadow : 0,
            y: isHovering ? Theme.Elevation.hoverShadowY : 0
        )
        .scaleEffect(isHovering ? Theme.Elevation.hoverScale : 1)
        .animation(Theme.Motion.hover, value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // One thing to a screen reader, not a strip of pictures beside two
        // strings: the artwork is decoration and the name is the control.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(genre.name)
        .accessibilityValue("\(genre.count) titles")
    }

    @ViewBuilder
    private var background: some View {
        let entries = Array(drawable.prefix(3))
        if entries.isEmpty {
            typographicFallback
        } else {
            mosaic(entries)
        }
    }

    /// Equal vertical slices, one per title.
    ///
    /// Vertical rather than a 2×2 grid because the card is 16:9 and a poster is
    /// 2:3 — a third of a 16:9 card is very nearly portrait, so each slice shows
    /// most of a poster instead of a band cropped out of its middle.
    private func mosaic(_ entries: [LibraryEntry]) -> some View {
        let sliceWidth = (width - seam * CGFloat(entries.count - 1)) / CGFloat(entries.count)
        return HStack(spacing: seam) {
            ForEach(entries) { entry in
                RemoteImage(
                    request: .poster(
                        for: entry, serverURL: serverURL, width: sliceWidth, scale: scale
                    ),
                    pipeline: pipeline,
                    // Text is drawn on this. See `Theme.Palette.artworkPlaceholder`.
                    carriesText: true
                )
                .frame(width: sliceWidth, height: height)
                .clipped()
            }
        }
        // Bottom-weighted rather than a flat wash: the top of the artwork stays
        // the picture, and the name gets its contrast where it sits.
        .overlay {
            LinearGradient(
                colors: [.clear, Theme.Palette.onArtwork, Theme.Palette.onArtworkStrong],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// The genre's own initial, set enormous and clipped by the card. A library
    /// with no artwork at all still gets a row of distinct cards rather than a row
    /// of grey rectangles — the tint above does the rest of that work.
    private var typographicFallback: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Theme.Palette.surfaceRaised, Theme.Palette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(genre.name.prefix(1))
                .font(.system(size: height, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.10))
                .offset(x: height * 0.14, y: -height * 0.22)
        }
    }

    /// Diagonal, from the label's own corner outwards, so the strongest part of
    /// the wash is under the text and the far corner stays photograph.
    private var tint: some View {
        LinearGradient(
            colors: [Theme.Genre.tint(for: genre.name), .clear],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(genre.name)
                .font(Theme.Font.genreTitle)
                .foregroundStyle(textColour)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(genre.count) titles")
                .font(Theme.Font.captionLarge)
                .foregroundStyle(mutedTextColour)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
    }

    /// White over a photograph, the page's own colour over the drawn fallback —
    /// white on the light-mode surface would be unreadable.
    private var hasArtwork: Bool { !drawable.isEmpty }
    private var textColour: Color {
        hasArtwork ? Theme.Palette.onArtworkText : Theme.Palette.textPrimary
    }
    private var mutedTextColour: Color {
        hasArtwork ? Theme.Palette.onArtworkTextMuted : Theme.Palette.textMuted
    }
}
