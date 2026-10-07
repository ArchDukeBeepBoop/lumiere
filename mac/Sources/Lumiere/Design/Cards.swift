import SwiftUI
import LumiereKit

/// A poster tile. The unit of the library grid and most shelves.
struct PosterCard: View {
    let entry: LibraryEntry
    let serverURL: URL
    let pipeline: ImagePipeline
    var width: CGFloat = Theme.Art.posterWidth
    var showsTitle: Bool = true
    /// Right-click actions. Optional so cards in contexts without an AppModel — the
    /// demo, previews — simply have no menu rather than a broken one.
    var metadata: MetadataActions?
    /// Replaces the title where the item's own name is not the useful one.
    ///
    /// One caller, and the same one `WideCard` has: a wall of loose video files,
    /// where the name Jellyfin's filename cleaner produced is often the same string
    /// for a dozen different files and the filename is the only thing that tells
    /// them apart. See `FolderBrowserView.fileTitle`.
    var titleOverride: String?
    /// Replaces the line under the title where the computed one is redundant.
    ///
    /// One caller: the season shelf on a series page, where every card would
    /// otherwise be captioned with the name of the show you are already looking at.
    /// Nil everywhere else, which keeps `TitleFormatter` the single answer to
    /// "what does this card say" for every other surface.
    var subtitleOverride: String?

    @State private var isHovering = false
    @Environment(\.displayScale) private var scale
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle
    @Environment(\.folderLibraryIds) private var folderLibraryIds
    /// Which libraries are anime, so the line under the title can lead with the
    /// studio there. The card cannot tell from the item — see `MetadataLine.kind`.
    @Environment(\.animeLibraryIds) private var animeLibraryIds
    /// So a tile can say it is being re-scraped. See `AppModel.refreshingItemIds`.
    @Environment(AppModel.self) private var app: AppModel?
    @AppStorage(Preference.typeAwareCardLines.name) private var typeAwareCardLines
        = Preference.typeAwareCardLines.defaultValue
    @AppStorage("showsUnwatchedBadges") private var showsUnwatchedBadges = true
    @AppStorage(UnwatchedMarker.storageKey) private var unwatchedMarker = UnwatchedMarker.corner

    /// Whether this card is being drawn at home-shelf size.
    ///
    /// Derived from the width rather than passed in, because everything that
    /// changes at the larger size — corner radius, label size, badge size — is a
    /// consequence of the width and nothing else. A flag would let a call site set
    /// one without the other, and it would also miss the library grid, whose tile
    /// slider can be dragged up to exactly this size.
    private var isLarge: Bool { width >= Theme.Art.shelfPosterWidth }
    private var corner: CGFloat {
        isLarge ? Theme.Radius.posterLarge : Theme.Radius.poster
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            artwork
            if showsTitle { labels }
        }
        .frame(width: width)
        .modifier(MetadataContextMenu(actions: metadata))
        .contentShape(Rectangle())
        .onHover { isHovering = $0; HomeAmbient.shared.hover(entry, $0) }
    }

    /// What a tile looks like while its metadata is being re-scraped.
    ///
    /// A veil and a spinner over the poster itself, rather than a status line
    /// somewhere else on the page: the answer to "did that do anything" has to
    /// be on the thing that was clicked.
    @ViewBuilder
    private var refreshingVeil: some View {
        if app?.refreshingItemIds.contains(entry.item.id) == true {
            ZStack {
                Rectangle().fill(.black.opacity(0.45))
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            .transition(.opacity)
        }
    }

    /// The line under the title, chosen by what the title is.
    ///
    /// Only on the metadata title style: the filename styles exist to show you
    /// the file, and a studio underneath one is not what was asked for.
    private var cardSubtitle: String? {
        guard titleStyle == .metadataTitle, typeAwareCardLines else {
            return TitleFormatter.subtitle(for: entry.item, style: titleStyle)
        }
        let kind = MetadataLine.kind(
            for: entry.item,
            isAnimeLibrary: entry.item.libraryId.map(animeLibraryIds.contains) ?? false
        )
        return MetadataLine.cardLine(
            for: entry, kind: kind, studio: MetadataLine.primaryStudio(entry.item)
        ) ?? TitleFormatter.subtitle(for: entry.item, style: titleStyle)
    }

    @ViewBuilder
    private var artwork: some View {
        artworkContent
            .frame(width: width, height: width / Theme.Art.posterAspect)
            .coverHeldBack(libraryId: entry.item.libraryId, isHovering: isHovering)
            .keyboardCard(id: entry.id, cornerRadius: corner)
        .overlay(alignment: .bottom) { progressBar }
        .overlay(alignment: .topTrailing) { unwatchedBadge }
        .overlay { refreshingVeil }
        // Clipped after the overlays, not before. The unwatched corner used to be
        // added on top of an already-clipped image, so its square edge overhung the
        // rounded one — the orange marker looked like it had been pasted on. Clipping
        // last makes the badge and the progress bar follow the card's own shape.
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .tvLift(corner: corner, size: CGSize(width: width, height: width / Theme.Art.posterAspect))
        // A lift rather than a ring. The gold stroke that used to mark the hovered
        // card competed with the artwork — on a shelf of anime covers it read as a
        // badge on the tile rather than as a cursor, and the 2pt border also ate
        // into the poster's own edge.
        // Radius zero when idle, not merely a clear colour. A shadow left in the
        // tree at full radius gives every card an offscreen buffer whether or not
        // anything is drawn into it — on a home screen of a few hundred cards that
        // measured 375 MB resident against 171 MB without it.
        .shadow(
            color: isHovering ? Theme.Palette.cardShadow : .clear,
            radius: isHovering ? Theme.Elevation.hoverShadow : 0,
            y: isHovering ? Theme.Elevation.hoverShadowY : 0
        )
        .scaleEffect(isHovering ? Theme.Elevation.hoverScale : 1)
        .animation(Theme.Motion.hover, value: isHovering)
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress = entry.progress {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.Palette.onArtwork)
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)
        }
    }

    /// Infuse's unwatched marker: a small filled corner. Only on things you can
    /// actually watch — a folder being "unwatched" means nothing.
    @ViewBuilder
    private var unwatchedBadge: some View {
        if showsUnwatchedBadges, isUnwatched, unwatchedMarker == .count,
           let left = entry.userData?.unplayedItemCount,
           entry.item.itemType == .series || entry.item.itemType == .season
            || entry.item.itemType == .boxSet {
            UnwatchedCountBadge(count: left, isLarge: isLarge)
        } else if showsUnwatchedBadges, isUnwatched {
            // Scaled with the card. A 22pt marker on a 200pt poster is a speck —
            // the corner has to stay the same *fraction* of the tile to keep
            // reading as a folded corner rather than a dot.
            // A dark edge along the fold, so the corner holds its shape on
            // artwork the same colour as it.
            UnwatchedCorner()
                .fill(Theme.Palette.unwatched)
                .overlay { UnwatchedCorner().stroke(.black.opacity(0.3), lineWidth: 1) }
                .frame(width: isLarge ? 30 : 22, height: isLarge ? 30 : 22)
        }
    }

    private var isUnwatched: Bool { entry.showsUnwatchedMarker }

    /// A drawn card when there is no poster to fetch, rather than an empty
    /// rectangle. `WideCard` has always done this; `PosterCard` did not, which is
    /// why a wall of loose video files — nothing scrapes them, so none has artwork —
    /// came out as rows of blank grey tiles and had to be given 16:9 cards instead.
    /// With a fallback here the shape is a free choice again.
    @ViewBuilder
    private var artworkContent: some View {
        if let request = ImageRequest.poster(
            for: entry, serverURL: serverURL, width: width, scale: scale
        ) {
            RemoteImage(request: request, pipeline: pipeline)
        } else {
            GeneratedThumb(
                title: titleOverride
                    ?? FolderTitle.title(for: entry, style: titleStyle, folderLibraryIds: folderLibraryIds),
                subtitle: titleOverride == nil
                    ? TitleFormatter.subtitle(for: entry.item, style: titleStyle)
                    : nil
            )
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Full strength whether or not the card is hovered. Dimming every
            // unhovered title made a shelf of twenty look greyed out — the
            // hierarchy that matters is title against subtitle, not hovered
            // against not.
            Text(titleOverride ?? FolderTitle.title(for: entry, style: titleStyle, folderLibraryIds: folderLibraryIds))
                .font(isLarge ? Theme.Font.cardTitleLarge : Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                // Two lines, always exactly two, and cut from the middle.
                //
                // This let a filename wrap to its full length on the reasoning that
                // "the grid aligns rows to the top, so an uneven label costs
                // nothing". That was wrong: a `LazyVGrid` row is as tall as its
                // tallest cell, so one five-line filename pushes the whole next row
                // down while a row of short names stays tight. The result is folders
                // and files sitting at wildly different distances from each other —
                // which is exactly what a wall of tiles must not do.
                //
                // `reservesSpace` is the half that makes it uniform: without it a
                // one-line name still yields a shorter cell than a two-line one.
                // Middle truncation because these names differ from each other at
                // the back as often as the front — a release group and a resolution
                // live there — and the full name is on the item's own page.
                .lineLimit(titleOverride == nil ? (titleStyle == .metadataTitle ? 1 : 2) : 2,
                           reservesSpace: titleOverride != nil)
                .truncationMode(.middle)
            if let subtitle = subtitleOverride ?? cardSubtitle {
                Text(subtitle)
                    .font(isLarge ? Theme.Font.captionLarge : Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineLimit(1)
            }
        }
    }
}

/// The corner triangle. Drawn rather than an SF Symbol so it sits flush into the
/// poster's rounded corner instead of floating above it.
