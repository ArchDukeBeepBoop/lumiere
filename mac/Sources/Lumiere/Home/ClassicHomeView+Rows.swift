import SwiftUI
import LumiereKit

/// The two rows on the Classic home screen that are lists rather than selections.
///
/// Split from ClassicHomeView.swift for the project's 300-line limit, and they
/// belong together: Continue Watching and Next Up are the same idea seen from either
/// side of an episode ending, so anything true of one — how far it reaches, when it
/// offers a See All, what a card does when clicked — has to stay true of the other.
/// Sitting in one file is what makes a divergence between them visible.
///
/// Not private, either of them: Swift scopes `private` to the file, and the body
/// that draws them is in ClassicHomeView.swift.
extension ClassicHomeView {

    /// The big cards at the top: everything started and not finished, newest first.
    ///
    /// It used to take the first four. That reads as a design decision — "carry on
    /// where you left off", not a second library — and it is the wrong one, because
    /// this is the only row in the app that is a list of *unfinished business*
    /// rather than a selection. Twelve were fetched, four were drawn, and on this
    /// library thirty-one things had been started: twenty-seven of them were
    /// nowhere on the home screen. A row you scroll is a much smaller cost than a
    /// title you cannot find.
    ///
    /// Built from `Shelf` rather than its own ScrollView so it inherits the same
    /// header, insets and hover room as everything under it. Hand-rolled, it was
    /// the one row on this screen whose tiles did not line up with the rest and
    /// the only one with no title over it.
    var continueRow: some View {
        // Untouched by the hero above it, which no longer draws from this list at
        // all: the spotlight is things you have not started, so nothing here is
        // duplicated up there and nothing needs dropping from the row.
        Shelf(
            title: "Continue Watching",
            // Once the strip is long enough to hide its own end. See
            // `HomeModel.seeAllThreshold`.
            action: model.resume.count > HomeModel.seeAllThreshold
                ? onSeeAllResume : nil,
            itemCount: model.resume.count, itemWidth: Theme.Art.continueCardWidth
        ) {
            ForEach(model.resume) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    WideCard(
                        entry: entry, serverURL: serverURL,
                        pipeline: pipeline, width: Theme.Art.continueCardWidth,
                        preferSeriesThumb: true,
                        // The disc on the still now starts the episode instead of
                        // opening its page, which is what a play button on a
                        // half-watched card has always looked like it would do.
                        metadata: shelfActions(for: entry),
                        onPlay: { app?.nowPlayingItemId = entry.item.id }
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The next unwatched episode of everything in progress.
    ///
    /// Posters rather than the wide cards above, and that is the one place the two
    /// rows differ on purpose: a Continue Watching card is a still with a progress
    /// bar because how far in you are is the point of it, and nothing here has been
    /// started. Everything else about it now matches — it reaches as far
    /// (`HomeModel.nextUpLength`, which was twelve), and it offers the same See All
    /// at the same length, which opens the same grid grouped by library.
    /// One of the two progress shelves. Same furniture as Next Up — these are
    /// the same kind of offer, and giving them a different card would say they
    /// were a different kind of thing.
    func progressRow(
        _ title: String, entries: [LibraryEntry], action: (() -> Void)? = nil
    ) -> some View {
        Shelf(
            title: title, subtitle: serverName, action: action,
            itemCount: entries.count, itemWidth: Theme.Art.shelfPosterWidth
        ) {
            ForEach(entries) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    PosterCard(
                        entry: entry, serverURL: serverURL,
                        pipeline: pipeline, width: Theme.Art.shelfPosterWidth,
                        metadata: shelfActions(for: entry)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    var nextUpRow: some View {
        Shelf(
            title: model.nextUpTitle, subtitle: serverName,
            action: model.nextUpEntries.count > HomeModel.seeAllThreshold
                ? onSeeAllNextUp : nil,
            itemCount: model.nextUpEntries.count, itemWidth: Theme.Art.continueCardWidth
        ) {
            // Stills, as Continue Watching has them: an episode is a moment in a
            // show, and the TV app draws what is next as the frame you will see.
            ForEach(model.nextUpEntries) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    WideCard(
                        entry: entry, serverURL: serverURL,
                        pipeline: pipeline, width: Theme.Art.continueCardWidth,
                        preferSeriesThumb: true,
                        metadata: shelfActions(for: entry),
                        onPlay: { app?.nowPlayingItemId = entry.item.id },
                        isNew: model.newEpisodeIds.contains(entry.id)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One section of the home screen.
    ///
    /// A `switch` over the order rather than a sequence of statements in `body`,
    /// which is the whole change: the arrangement is now data — read from
    /// preferences, reorderable in Settings — and this maps each entry to the view
    /// that draws it. Sections with nothing to show draw nothing, exactly as they
    /// did when the order was hard-coded.
    @ViewBuilder
    func view(for section: HomeSection) -> some View {
        switch section {
        case .spotlight:
            // A spotlight of things worth starting, which is how Apple TV opens.
            // The same `HeroSpotlight` the Hero layout draws, not a second one: it
            // carries the logo, the metadata line, the resume track and the Play
            // button, and two of them would be two things to keep in step.
            if let capabilities {
                HeroSpotlight(
                    entries: model.heroEntries,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    capabilities: capabilities,
                    onPlay: { app?.nowPlayingItemId = $0 },
                    onRefresh: { await model.refreshSpotlight(libraries: libraries) },
                    reasons: model.spotlightReasons
                )
            }
            HomeNewsLine(text: model.newsLine)

        case .quickLinks:
            // With the sidebar hidden this row is the only way into a library.
            // Search is one of these pills, which is why the home screen needs no
            // field of its own.
            HomeQuickLinks(app: app)

        case .libraries:
            LibraryShelf(
                libraries: model.libraryCards, serverURL: serverURL,
                pipeline: pipeline, onOpen: onOpenLibrary
            )

        case .continueWatching:
            if !model.resume.isEmpty { continueRow }

        case .genres:
            GenreShelf(
                genres: model.genreCards, serverURL: serverURL, pipeline: pipeline
            )

        case .nextUp:
            if !model.nextUpEntries.isEmpty { nextUpRow }

        case .finishSeason:
            if !model.mergesUpNext, !model.finishSeason.isEmpty {
                progressRow("Finish the season", entries: model.finishSeason)
            }

        case .becauseYouWatched:
            if let because = model.becauseYouWatched {
                progressRow(because.title, entries: because.entries)
            }

        case .continueSeries:
            if !model.mergesUpNext, !model.continueSeries.isEmpty {
                progressRow("Continue the series", entries: model.continueSeries)
            }

        case .forgotten:
            if !model.forgotten.isEmpty {
                progressRow(
                    "Forgotten", entries: model.forgotten,
                    action: model.forgotten.count > HomeModel.seeAllThreshold
                        ? onSeeAllForgotten : nil
                )
            }

        case .recentlyAdded:
            // Nothing, deliberately. Classic says the same thing one library at a
            // time with its Latest rows, and drawing both would show the same
            // handful of titles twice on one screen. The section still exists in
            // the order so that moving it in Settings, switching to the Hero
            // layout, and finding it where you left it all agree.
            EmptyView()

        // Three rows, not two. Anime and live-action television share a Jellyfin
        // collection type and nothing else, and ranked together the anime library's
        // ratings pushed television out of its own chart. See `LibraryKinds`.
        case .topFilms:
            topShelf("Top 10 Films", kind: .films, entries: model.topFilms)
        case .topSeries:
            topShelf("Top 10 Series", kind: .series, entries: model.topSeries)
        case .topAnime:
            topShelf("Top 10 Anime", kind: .anime, entries: model.topAnime)

        case .latest(let libraryId):
            // Nothing at all for a library whose shelf came back empty — the same
            // silence `libraryShelves` produced by not including it.
            if let shelf = model.libraryShelves.first(where: { $0.library.id == libraryId }) {
                latestRow(shelf.library, entries: shelf.entries)
            }
        }
    }

    /// The "Latest <library>" row.
    ///
    /// See All opens the fifty most recent rather than the library itself: it used
    /// to open exactly what picking the library opens, which made it a second
    /// button for something already on screen and lost the shelf's own ordering.
    /// See `LatestBrowseView`.
    func latestRow(_ library: LibraryRecord, entries: [LibraryEntry]) -> some View {
        Shelf(
            title: "Latest \(library.name)",
            subtitle: serverName,
            action: { onSeeAllLatest(library) },
            itemCount: entries.count,
            itemWidth: Theme.Art.shelfPosterWidth
        ) {
            ForEach(entries) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    PosterCard(
                        entry: entry, serverURL: serverURL,
                        pipeline: pipeline, width: Theme.Art.shelfPosterWidth,
                        metadata: shelfActions(for: entry)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
