import SwiftUI
import LumiereKit

/// The Hero layout's rows, one per `HomeSection`.
///
/// Split from HeroHomeView.swift for the project's 300-line limit, and it is the
/// same shape as ClassicHomeView+Rows.swift on purpose: the two layouts draw the
/// same sections in the same user-chosen order, and differ only in how a row looks.
/// Keeping the mapping in matching files is what makes a divergence between them
/// something you can see rather than something you find later.
extension HeroHomeView {

    @ViewBuilder
    func view(for section: HomeSection) -> some View {
        switch section {
        case .spotlight:
            // Nothing above the backdrop. The shelf filter used to open this
            // layout, which put a text field on top of the one thing the layout
            // exists for.
            HeroSpotlight(
                entries: model.heroEntries,
                pipeline: pipeline,
                serverURL: serverURL,
                capabilities: capabilities,
                onPlay: { app?.nowPlayingItemId = $0 },
                onRefresh: { await model.refreshSpotlight(libraries: shelfLibraries) },
                reasons: model.spotlightReasons
            )
            HomeNewsLine(text: model.newsLine)

        case .quickLinks:
            // Below the hero rather than above it by default: the backdrop is the
            // whole reason to choose this layout, and a strip of navigation on top
            // of it would be the Classic screen with a picture underneath.
            HomeQuickLinks(app: app)

        case .libraries:
            LibraryShelf(
                libraries: model.libraryCards, serverURL: serverURL,
                pipeline: pipeline, onOpen: onOpenLibrary
            )

        case .continueWatching:
            if !model.resume.isEmpty {
                Shelf(
                    title: "Continue watching",
                    action: model.resume.count > HomeModel.seeAllThreshold
                        ? onSeeAllResume : nil,
                    itemCount: model.resume.count, itemWidth: Theme.Art.continueCardWidth
                ) {
                    ForEach(model.resume) { entry in
                        NavigationLink(value: DetailRoute.forEntry(entry)) {
                            WideCard(
                                entry: entry, serverURL: serverURL, pipeline: pipeline,
                                width: Theme.Art.continueCardWidth,
                                preferSeriesThumb: true,
                                metadata: shelfActions(for: entry),
                                onPlay: { app?.nowPlayingItemId = entry.item.id }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .genres:
            GenreShelf(
                genres: model.genreCards, serverURL: serverURL, pipeline: pipeline
            )

        case .nextUp:
            if !model.nextUpEntries.isEmpty {
                Shelf(
                    title: model.nextUpTitle,
                    action: model.nextUpEntries.count > HomeModel.seeAllThreshold
                        ? onSeeAllNextUp : nil,
                    itemCount: model.nextUpEntries.count, itemWidth: Theme.Art.continueCardWidth
                ) {
                    ForEach(model.nextUpEntries) { entry in
                        NavigationLink(value: DetailRoute.forEntry(entry)) {
                            WideCard(
                                entry: entry, serverURL: serverURL, pipeline: pipeline,
                                width: Theme.Art.continueCardWidth,
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

        case .finishSeason:
            if !model.mergesUpNext, !model.finishSeason.isEmpty {
                posterShelf("Finish the season", entries: model.finishSeason, action: nil)
            }

        case .becauseYouWatched:
            if let because = model.becauseYouWatched {
                posterShelf(because.title, entries: because.entries, action: nil)
            }
        case .continueSeries:
            if !model.mergesUpNext, !model.continueSeries.isEmpty {
                posterShelf("Continue the series", entries: model.continueSeries, action: nil)
            }

        case .forgotten:
            if !model.forgotten.isEmpty {
                posterShelf(
                    "Forgotten", entries: model.forgotten,
                    action: model.forgotten.count > HomeModel.seeAllThreshold
                        ? onSeeAllForgotten : nil
                )
            }

        case .recentlyAdded:
            if !model.recentlyAddedShown.isEmpty {
                posterShelf("Recently added", entries: model.recentlyAddedShown, action: nil)
            }

        case .topFilms:
            topShelf("Top 10 Films", kind: .films, entries: model.topFilms)
        case .topSeries:
            topShelf("Top 10 Series", kind: .series, entries: model.topSeries)
        case .topAnime:
            topShelf("Top 10 Anime", kind: .anime, entries: model.topAnime)

        case .latest(let libraryId):
            if let shelf = model.libraryShelves.first(where: { $0.library.id == libraryId }) {
                posterShelf(
                    shelf.library.name, entries: shelf.entries,
                    action: { onSeeAllLatest(shelf.library) }
                )
            }
        }
    }

    /// A row of posters. Four callers had this written out four times, differing
    /// only in title and action — which is how the Next Up row here ended up
    /// without the See All that Classic's had.
    func posterShelf(
        _ title: String, entries: [LibraryEntry], action: (() -> Void)?
    ) -> some View {
        Shelf(
            title: title,
            action: action,
            itemCount: entries.count,
            itemWidth: Theme.Art.shelfPosterWidth
        ) {
            ForEach(entries) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    PosterCard(
                        entry: entry, serverURL: serverURL, pipeline: pipeline,
                        width: Theme.Art.shelfPosterWidth,
                        metadata: shelfActions(for: entry)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
