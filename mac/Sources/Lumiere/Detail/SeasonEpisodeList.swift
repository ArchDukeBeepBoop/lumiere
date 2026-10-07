import SwiftUI
import LumiereKit

/// Season picker plus a horizontal strip of episode thumbnails.
///
/// Selecting a thumbnail changes what the hero above shows — title, synopsis,
/// rating, actions — without navigating anywhere. That in-place browsing is the
/// whole point of the layout: dozens of episodes are one glance away rather than
/// a stack of pushed pages.
struct SeasonEpisodeList: View {
    let model: DetailModel
    let pipeline: ImagePipeline
    let serverURL: URL
    /// Opens the metadata editor for one episode. A wrong title lands on a single
    /// episode as often as on a show, and the header above only ever edits the
    /// series — so the strip needs its own way in.
    var onEditEpisode: ((String) -> Void)?
    /// Opens the artwork picker on a *season*, which is the only way one ever gets
    /// its own backdrop: no season in a real library arrives with one, so the
    /// per-season header art depends entirely on this being reachable.
    var onSeasonArtwork: ((String) -> Void)?
    /// Opens the filename-repair preview for the whole series. Lives beside the
    /// season picker because that is where a merged series is visible as one: a
    /// picker offering one season for sixteen shows' worth of episodes.
    var onRepairEpisodes: (() -> Void)?
    /// Replaces one episode's still with a frame out of its own file. Per-episode
    /// as well as per-series because the duplicate-thumbnail problem is not always
    /// a whole series: one episode matched to the wrong listing is the common case.
    var onGenerateThumbnail: ((String) -> Void)?
    /// The artwork picker for one episode — which is also the only way to *delete*
    /// an image, and it was reachable for series and films but not for episodes.
    var onEpisodeArtwork: ((String) -> Void)?
    /// The two ways out. Nil where the owner has switched removal off.
    var onRemoveEpisode: ((LibraryEntry) -> Void)?
    var onDeleteEpisode: ((LibraryEntry) -> Void)?
    /// Marks one episode watched. `DetailModel.setEpisodeWatched` has existed since
    /// the detail pages landed and nothing ever called it: an episode could only be
    /// marked by making it the hero first and using the header's action row.
    var onToggleEpisodeWatched: ((String, Bool) -> Void)?
    /// Right-click actions for a season poster. Nil where there is no client to
    /// write with, which is also when the shelf draws no menu at all.
    var seasonActions: ((LibraryEntry) -> MetadataActions?)?
    /// Plays one episode, from the disc on its thumbnail.
    var onPlayEpisode: ((String) -> Void)?

    // Not private: SeasonEpisodeList+Paging.swift draws the strip and its chevrons,
    // and Swift's `private` is file-scoped. An extension cannot add stored
    // properties, so the state that file needs has to be declared here.
    @Environment(\.displayScale) var scale
    @AppStorage(Preference.separatesExtras.name) private var separatesExtras
        = Preference.separatesExtras.defaultValue
    @State private var isHoveringRepair = false
    // Not private: the button lives in SeasonEpisodeList+Artwork.swift, and an
    // extension cannot hold state of its own.
    @State var isHoveringStills = false
    /// How far the strip has been scrolled, how wide it is, and how much of it is
    /// on screen.
    ///
    /// Measured from live geometry rather than counted in pages. A page counter
    /// desynchronises the first time someone scrolls the strip by hand — and then
    /// hides an arrow that still has somewhere to go, which is worse than having
    /// no arrow at all.
    @State var scrollOffset: CGFloat = 0
    @State var contentWidth: CGFloat = 0
    @State var viewportWidth: CGFloat = 0

    var body: some View {
        // Built by hand rather than with `DetailShelf` because this is the one
        // section whose title is a control: the season picker stands where "Cast"
        // or "Extras" would. It still carries that wrapper's measurements — `sm`
        // to the strip, the page margin on the header and on the cells, the scroll
        // view full width — so it lines up with every shelf below it.
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                if model.seasons.count > 1 {
                    seasonPicker
                        .contextMenu {
                            if let onSeasonArtwork, let season = model.selectedSeasonId {
                                Button("Choose Season Artwork…") { onSeasonArtwork(season) }
                            }
                        }
                } else {
                    // Set exactly as a home shelf's title is, tracking included:
                    // the whole point of this section is that it is the series
                    // page's equivalent of a shelf.
                    Text("Episodes")
                        .font(Theme.Font.shelfTitle)
                        .tracking(-0.4)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Spacer(minLength: Theme.Space.lg)
                if model.canFetchEpisodeImages { fetchStillsButton }
                if let onRepairEpisodes {
                    EpisodeOrderButton(repository: model.repository, seriesId: model.itemId)
                    QueueSubtitlesButton(
                        repository: model.repository, seriesId: model.itemId,
                        seasonId: model.selectedSeasonId, seasonName: selectedSeasonName
                    )
                    repairButton(onRepairEpisodes)
                }
            }
            .detailMargin()

            if let status = model.episodeImageStatus {
                Text(status)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .detailMargin()
            }

            if model.episodes.isEmpty {
                Text(emptyMessage)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .padding(.vertical, Theme.Space.lg)
                    .detailMargin()
            } else {
                strip
            }

            // Under the episodes, not above them. The strip is what this section is
            // for — the seasons are how you change which strip you are looking at —
            // and putting a second row of artwork between the header and the
            // episodes pushed the episodes below the fold on a laptop.
            if !model.seasons.isEmpty {
                SeasonPosterShelf(
                    seasons: model.seasons,
                    selectedId: model.selectedSeasonId,
                    serverURL: serverURL,
                    pipeline: pipeline,
                    onSelect: { id in Task { await model.selectSeason(id) } },
                    actions: seasonActions,
                    episodeCounts: model.seasonEpisodeCounts
                )
            }
        }
    }

    /// What an empty strip says, which depends on why it is empty.
    private var emptyMessage: String {
        if !model.didLoadEpisodes { return "Loading episodes…" }
        if model.seasons.isEmpty { return "No episodes cached yet." }
        if !model.didLoadEpisodes { return "Loading episodes…" }
        return "No episodes in this season."
    }

    /// A `Menu` rather than a `Picker`, so the season name can *be* the section
    /// heading.
    ///
    /// A menu-styled Picker draws its own bordered box at the system's control
    /// size, and nothing inside it can be set at 26pt — the `.font` modifier on it
    /// was quietly doing nothing. The result was that on a one-season show the
    /// section was titled in bold display type and on a multi-season show it was
    /// titled by a small grey pop-up button, which is the wrong way round: the
    /// page with more to navigate got the weaker control.
    ///
    /// Behaviour is unchanged — each item calls `selectSeason`, the same thing the
    /// binding did — and the tick marks the current season the way the pop-up's
    /// own did.
    /// Seasons as a row of pills, the current one filled, as Apple TV draws
    /// them — every season one click away rather than behind a menu. The
    /// specials (Season 0, OVAs, creditless openings) follow after a gap.
    @ViewBuilder
    private var seasonPicker: some View {
        let seasons = model.seasons.filter { !separatesExtras || !$0.isSpecialsSeason }
        let extras = separatesExtras ? model.seasons.filter(\.isSpecialsSeason) : []
        if seasons.count + extras.count <= 1 {
            Text(selectedSeasonName)
                .font(Theme.Font.shelfTitle)
                .tracking(-0.4)
                .foregroundStyle(Theme.Palette.textPrimary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(seasons) { seasonPill($0) }
                    if !extras.isEmpty {
                        Spacer().frame(width: Theme.Space.md)
                        ForEach(extras) { seasonPill($0) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func seasonPill(_ season: LibraryEntry) -> some View {
        let current = season.id == (model.selectedSeasonId ?? model.seasons.first?.id)
        return Button {
            Task { await model.selectSeason(season.id) }
        } label: {
            Text(separatesExtras ? season.seasonPickerName : season.item.name)
                .font(.system(size: 14, weight: current ? .semibold : .medium))
                .foregroundStyle(current ? Theme.Palette.canvas : Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 7)
                .background(current ? Theme.Palette.textPrimary : Theme.Palette.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.hover, value: current)
    }

    private var selectedSeasonName: String {
        model.seasons.first { $0.id == model.selectedSeasonId }?.seasonPickerName
            ?? model.seasons.first?.seasonPickerName
            ?? "Season"
    }

    /// The same capsule "See All" wears on Home. It was four grey words beside a
    /// heading, which is exactly the shape that pass replaced there.
    private func repairButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "wand.and.rays").font(Theme.Font.badge)
                Text("Fix from Filenames…")
            }
            .font(Theme.Font.cardTitle)
            .foregroundStyle(
                isHoveringRepair ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
            )
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(
                isHoveringRepair ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                in: Capsule()
            )
            .overlay { Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .labelledHelp("Rebuild these episodes' numbering and titles from the "
            + "filenames on disk, when the scraper has merged or "
            + "misnumbered them")
        .onHover { isHoveringRepair = $0 }
        .animation(Theme.Motion.hover, value: isHoveringRepair)
    }

    // The strip itself, its per-episode context menus and the chevrons that page
    // it live in SeasonEpisodeList+Paging.swift, for the 300-line rule.
}
