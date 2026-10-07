import SwiftUI
import LumiereKit

/// Backdrop, poster, title block and actions.
struct DetailHeader: View {
    let model: DetailModel
    let entry: LibraryEntry
    let pipeline: ImagePipeline
    let serverURL: URL
    let capabilities: SystemCapabilities
    let onPlay: () -> Void
    /// nil for items that are not a single playable file — a series has no one file
    /// to download, and offering the button there would do nothing.
    let download: DownloadAction?

    @Environment(\.displayScale) private var scale
    @Environment(\.folderLibraryIds) private var folderLibraryIds
    @Environment(\.animeLibraryIds) private var animeLibraryIds
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle
    @State private var isHoveringPlay = false

    /// Taller now that the poster no longer sits beside the text. Infuse leads a
    /// detail page with the wide art alone and no portrait thumbnail next to it —
    /// the poster is how you found the title in the grid, so repeating it here
    /// spends the best real estate on the page restating what you just clicked.
    private let backdropHeight: CGFloat = 460

    var body: some View {
        // The content, not the backdrop, defines the header's height. A ZStack
        // sized to the backdrop clips the title off the top the moment the
        // overview runs long — which it does for most films.
        content
            .padding(.top, 220)
            .background(alignment: .top) { backdrop }
    }

    private var backdrop: some View {
        GeometryReader { geometry in
            ZStack {
                RemoteImage(
                    request: .backdrop(
                        for: entry, serverURL: serverURL,
                        width: geometry.size.width, scale: scale
                    ),
                    pipeline: pipeline,
                    // Text is drawn on this. See `Theme.Palette.artworkPlaceholder`.
                    carriesText: true
                )
                .frame(width: geometry.size.width, height: backdropHeight)
                .clipped()

                // Only the band the text sits on. See `BackdropTextWash`.
                BackdropTextWash()
            }
        }
        .frame(height: backdropHeight)
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                // Both are drawn on the picture; see `metadataLine`.
                Group {
                    titleBlock
                    metadataLine
                }
                .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
                RatingChips(
                    community: entry.item.communityRating,
                    critic: model.detail?.criticRating
                )

                if !badges.isEmpty {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(badges, id: \.0) { text, role in
                            Badge(text: text, role: role)
                        }
                    }
                }

                if let tagline = model.detail?.taglines?.first, !tagline.isEmpty {
                    Text(tagline)
                        .font(Theme.Font.body)
                        .italic()
                        .foregroundStyle(Theme.Palette.textMuted)
                }

                if let overview = model.detail?.overview ?? entry.item.overview, !overview.isEmpty {
                    ExpandableText(text: overview, collapsedLines: 3)
                        .frame(maxWidth: DetailMetrics.readingMeasure, alignment: .leading)
                }

                creditsLine
                actions
                actionRow
            }
            Spacer(minLength: 0)
        }
        // The same page margin as the hero header and every shelf below it. This
        // view is what a series page shows for the moment before its episodes
        // arrive, so a different inset here would be a visible jump on every open.
        .padding(.horizontal, Theme.Space.shelfInset)
        .padding(.vertical, Theme.Space.xxl)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let logo = ImageRequest.logo(
            for: entry, serverURL: serverURL,
            width: DetailMetrics.logoWidth, scale: scale
        ) {
            RemoteImage(request: logo, pipeline: pipeline, contentMode: .fit)
                .frame(
                    maxWidth: DetailMetrics.logoWidth,
                    maxHeight: DetailMetrics.logoHeight,
                    alignment: .leading
                )
        } else {
            Text(FolderTitle.title(
                for: entry, style: titleStyle, folderLibraryIds: folderLibraryIds
            ))
                .font(Theme.Font.detailTitle)
                .foregroundStyle(Theme.Palette.onArtworkText)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: DetailMetrics.logoWidth, alignment: .leading)
        }
    }

    /// The title and this line begin inside the backdrop — `content` is inset 220pt
    /// into a 460pt picture — so both take the artwork colours. Everything below
    /// them runs off the picture onto the page and keeps the page's, because white
    /// on the light canvas is the same bug in the other direction.
    private var metadataLine: some View {
        Text(metadataParts.joined(separator: " · "))
            .font(Theme.Font.detailMeta)
            .foregroundStyle(Theme.Palette.onArtworkTextMuted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// What kind of thing this is decides what the line says.
    ///
    /// A film wants the runtime and who made it; a series wants how much is
    /// left; an anime wants the studio. One line for all three said the year and
    /// hoped. See `MetadataLine`.
    private var metadataParts: [String] {
        let kind = MetadataLine.kind(
            for: entry.item,
            isAnimeLibrary: entry.item.libraryId.map(animeLibraryIds.contains) ?? false
        )
        var parts = MetadataLine.parts(
            for: entry, kind: kind,
            director: model.directorName,
            studio: entry.item.primaryStudio
        )
        if let rating = entry.item.officialRating { parts.append(rating) }

        let genres = model.detail?.genres ?? entry.item.genreList
        if !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }

        // No season count appended here: `MetadataLine.series` and `.anime`
        // already carry one, and this line read "5 seasons · 12 unwatched ·
        // TV-14 · Drama · 5 seasons".
        return parts
    }

    @ViewBuilder
    private var creditsLine: some View {
        let directors = model.directors
        let writers = model.writers
        if !directors.isEmpty || !writers.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if !directors.isEmpty {
                    creditRow(directors.count == 1 ? "Director" : "Directors", directors)
                }
                if !writers.isEmpty {
                    creditRow(writers.count == 1 ? "Writer" : "Writers", writers)
                }
            }
        }
    }

    private func creditRow(_ label: String, _ names: [String]) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: 64, alignment: .leading)
            Text(names.prefix(3).joined(separator: ", "))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var badges: [(String, Badge.Role)] {
        BadgeBuilder.badges(for: model.selectedSource, capabilities: capabilities)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: Theme.Space.md) {
            // Kept identical to the hero header's Play, down to the hover lift.
            // The two headers swap places as a series page loads, and a primary
            // action that changes size mid-open reads as the page redrawing wrong.
            Button(action: onPlay) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "play.fill").font(.system(size: 16))
                    Text(playLabel).font(Theme.Font.playLabel)
                }
                .foregroundStyle(Theme.Palette.playButtonLabel)
                .frame(maxWidth: .infinity, minHeight: DetailMetrics.playButtonHeight)
                .background(Theme.Palette.playButton)
                .clipShape(
                    RoundedRectangle(cornerRadius: Theme.Radius.playControl, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .frame(width: DetailMetrics.actionColumnWidth)
            .scaleEffect(isHoveringPlay ? Theme.Elevation.hoverScale : 1)
            .animation(Theme.Motion.hover, value: isHoveringPlay)
            .onHover { isHoveringPlay = $0 }

            if model.hasMultipleVersions {
                versionPicker
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    /// The row of small actions Infuse puts under Play. Quiet glyphs, the same as
    /// the hero header's — this header is the pre-episode-load fallback for a
    /// series, and the two must not disagree about what a secondary action looks
    /// like as the page settles.
    private var actionRow: some View {
        HStack(spacing: Theme.Space.xs) {
            QuietIconButton(
                systemName: entry.isPlayed ? "eye.fill" : "eye",
                help: entry.isPlayed ? "Mark as unwatched" : "Mark as watched",
                isOn: entry.isPlayed
            ) {
                Task { await model.toggleWatched() }
            }
            QuietIconButton(
                systemName: entry.userData?.isFavorite == true ? "star.fill" : "star",
                help: entry.userData?.isFavorite == true
                    ? "Remove from favourites" : "Add to favourites",
                isOn: entry.userData?.isFavorite == true
            ) {
                Task { await model.toggleFavourite() }
            }

            if let download {
                QuietIconButton(
                    systemName: download.icon,
                    help: download.help,
                    isOn: download.isComplete
                ) {
                    Task { await download.act() }
                }
            }
        }
        .padding(.leading, -Theme.Space.sm)
    }

}
