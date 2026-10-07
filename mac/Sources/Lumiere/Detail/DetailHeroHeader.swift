import SwiftUI
import LumiereKit

/// The page's leading block: full-bleed backdrop, logo, and whatever is about to
/// play — its title, synopsis, rating and actions.
///
/// Used by both series and films. A series leads with whichever episode is on
/// screen while keeping the *show's* art behind it; a film is simply both at once.
/// Written against those two roles rather than against `DetailModel` so it does not
/// need to know which kind of page it is on.
///
/// Showing a series' own overview — a summary of the whole show — where someone
/// expects to read what this specific episode is about was the actual gap behind
/// "episode synopsis is missing": the text was there, just describing the wrong
/// thing.
struct DetailHeroHeader: View {
    /// What is being described and played: an episode on a series page, the film
    /// itself on a movie page.
    let hero: LibraryEntry
    /// Where the backdrop and logo come from — the series for an episode, so the art
    /// stays put as you step along the strip; the film itself for a movie.
    let artEntry: LibraryEntry
    let pipeline: ImagePipeline
    let serverURL: URL
    /// What kind of thing this is — "Thriller", "Drama". The classification line
    /// under the logo is the only place these appear on the page, which is why the
    /// About block below has no genre row; see the note there.
    let genres: [String]
    /// The season's episodes, in order, where there are any.
    ///
    /// Only so the page can say where you are in it. See `DominantFact`.
    var seasonEpisodes: [LibraryEntry] = []
    @AppStorage(Preference.showsOriginalTitle.name) var showsOriginalTitle
        = Preference.showsOriginalTitle.defaultValue
    @AppStorage(Preference.leadsWithProgress.name) var leadsWithProgress
        = Preference.leadsWithProgress.defaultValue
    let onPlay: () -> Void
    let onToggleWatched: () async -> Void
    let onToggleFavourite: () async -> Void
    /// What the star reflects and acts on, where that is not the hero.
    ///
    /// On a series page the hero is whichever *episode* the strip has selected, so
    /// the star favourited that episode — there was no way to say "I like this
    /// show", which is the thing anyone actually wants starred. A series is what
    /// Favourites is for; a single episode of one almost never is. The per-episode
    /// star stays on the episode's own right-click menu.
    /// What the star reflects and acts on, where that is not the hero.
    ///
    /// On a series page the hero is whichever *episode* the strip has selected, so
    /// the star favourited that episode — there was no way to say "I like this
    /// show", which is the thing anyone actually wants starred. A series is what
    /// Favourites is for; a single episode of one almost never is. The per-episode
    /// star stays on the episode's own right-click menu.
    var favouriteEntry: LibraryEntry?
    let download: DownloadAction?
    /// Opens the metadata editor for whatever this header describes. Nil where
    /// there is no client to write a change with.
    var onEditMetadata: (() -> Void)?
    /// The files this title has, and which one is chosen. Empty for the usual case
    /// of one file — the picker only appears when there is a choice to make.
    var versions: [MediaSource] = []
    var selectedVersion: Binding<String?>?

    @Environment(\.displayScale) private var scale
    // Not private: DetailHeroHeader+Meta.swift titles the episode line with it, and
    // Swift's `private` is file-scoped.
    @Environment(\.folderLibraryIds) var folderLibraryIds
    // Not private: DetailHeroHeader+Meta.swift sets the episode title with it, and
    // Swift's `private` is file-scoped.
    @AppStorage("titleStyle") var titleStyle: TitleStyle = .metadataTitle
    // Not private: DetailHeroHeader+Actions.swift draws the Play button, for the
    // same reason.
    @State var isHoveringPlay = false

    /// The column holding Play and the quiet actions. Not private:
    /// DetailHeroHeader+Actions.swift sizes the pill and the picker from it.
    let actionColumnWidth = DetailMetrics.actionColumnWidth

    /// The backdrop runs the full width at 16:9 — its real aspect — rather than a
    /// fixed height that crops it to a band. Wide art is the whole visual idea of
    /// this page, and a 460pt strip across a wide window threw most of it away.
    ///
    /// `Color.clear.aspectRatio(_:contentMode: .fit)` is what sizes it: it takes the
    /// width the column offers and derives the height from it, so the header stays
    /// 16:9 at any window size. A `GeometryReader` cannot do this on its own — it
    /// fills whatever it is handed and reports nothing back to its parent, so the
    /// height would have to be guessed from the screen, which is wrong the moment
    /// the sidebar is open.
    var body: some View {
        Color.clear
            .aspectRatio(Theme.Art.backdropAspect, contentMode: .fit)
            .overlay { backdrop }
            // Only the band the title and actions sit on. See `BackdropTextWash`.
            .overlay { BackdropTextWash() }
            .overlay(alignment: .bottomLeading) { content }
            .clipped()
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            GeometryReader { geometry in
                RemoteImage(
                    request: backdropRequest(width: geometry.size.width),
                    pipeline: pipeline,
                    // Text is drawn on this. See `Theme.Palette.artworkPlaceholder`.
                    carriesText: true
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }

        }
    }

    /// The show's own backdrop, not the episode's.
    ///
    /// The art behind the header is the *series'* identity, and it should not change
    /// as you move along the episode strip — stepping through a season made the whole
    /// page flicker between unrelated frame grabs. A series with no backdrop of its
    /// own still falls back to whichever episode is on screen, which is better than
    /// an empty header.
    private func backdropRequest(width: CGFloat) -> ImageRequest? {
        if let art = ImageRequest.backdrop(
            for: artEntry, serverURL: serverURL, width: width, scale: scale
        ) {
            return art
        }
        if let heroArt = ImageRequest.backdrop(
            for: hero, serverURL: serverURL, width: width, scale: scale
        ) {
            return heroArt
        }
        // Last resort: the poster, blurred behind the scrim. Plenty of shows and
        // films have a cover and no wide art at all, and those pages were rendering
        // as a flat slab of canvas colour — worse than a cropped poster, which at
        // least carries the title's own palette.
        return ImageRequest.poster(
            for: artEntry, serverURL: serverURL, width: width, scale: scale
        )
    }

    // MARK: - Overlaid content

    /// Apple TV's shape, in three bands: the logo, then a tight metadata line
    /// directly under it, then Play with the synopsis beside it.
    ///
    /// Two things were learned the hard way and are both preserved here. Play must
    /// not sit *above* the synopsis — stacking the whole header vertically pushed
    /// the episode strip off the bottom of the window — and the metadata line must
    /// not live in the action column, where "S1 E4 · 6 Aug 2026 · TV-MA · 24m ·
    /// 4K · Action, Drama" wraps to three lines inside 320pt. Giving the logo and
    /// the metadata the full width and splitting only the row beneath them keeps
    /// the header the same height as the two-column version while reading the way
    /// the TV app's does.
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            logo
            titleLine
            originalTitleLine
            dominantFactLine
            metadataLine

            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    playButton
                    actionRow
                    versionPicker
                }
                .frame(width: actionColumnWidth, alignment: .leading)

                readingColumn
                Spacer(minLength: 0)
            }
            .padding(.top, Theme.Space.sm)
        }
        .padding(.horizontal, Theme.Space.shelfInset)
        .padding(.bottom, Theme.Space.xxl)
        // For the shared components inside — the synopsis and the rating chips,
        // which are also used on the page below where the page colours are right.
        // This header's own labels take the artwork colours directly: SwiftUI does
        // not hand a view back an environment value its own body sets, so reading
        // the flag here would always see false.
        .onArtwork()
    }

    /// The series logo, not the episode's — an episode has no logo of its own, and
    /// the show's identity is what belongs over its own art. Falls back to the
    /// title so the block is never a hole.
    ///
    /// The fallback is not given a fixed height: a long title at `detailTitle`
    /// wants two or three lines, and clamping it to the logo's box either cut it
    /// off or left most shows' one-line names floating in dead space. It scales
    /// down rather than truncating, because a shortened film title is a worse
    /// answer than a slightly smaller one.
    @ViewBuilder
    private var logo: some View {
        if let request = ImageRequest.logo(
            for: artEntry, serverURL: serverURL,
            width: DetailMetrics.logoWidth, scale: scale
        ) {
            RemoteImage(request: request, pipeline: pipeline, contentMode: .fit)
                .frame(
                    width: DetailMetrics.logoWidth,
                    height: DetailMetrics.logoHeight,
                    alignment: .bottomLeading
                )
        } else {
            Text(FolderTitle.title(
                for: artEntry, style: titleStyle, folderLibraryIds: folderLibraryIds
            ))
                .font(Theme.Font.detailTitle)
                .foregroundStyle(Theme.Palette.onArtworkText)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: DetailMetrics.logoWidth, alignment: .bottomLeading)
        }
    }

    private var readingColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            // The episode's own synopsis, else the show's. A freshly added
            // episode has none until the naming pass reaches it, and a hero
            // with no text under a raw filename read as a page with nothing to
            // say — when the show had a synopsis all along.
            if let overview = [hero.item.overview, artEntry.item.overview]
                .compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                ExpandableText(text: overview, collapsedLines: 3)
            }

            RatingChips(community: hero.item.communityRating, critic: nil)
        }
        .frame(maxWidth: DetailMetrics.readingMeasure, alignment: .leading)
    }

    // The title line and the classification line beneath the logo live in
    // DetailHeroHeader+Meta.swift, for the project's 300-line rule.
}
