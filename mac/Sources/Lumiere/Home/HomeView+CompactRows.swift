import SwiftUI
import LumiereKit

/// Compact's sections, one per `HomeSection`, plus the paging wall underneath them.
///
/// Split from HomeView+Compact.swift for the project's 300-line limit. Compact draws
/// the same sections as the other two layouts and in the same user-chosen order; the
/// difference is entirely in the cell — grids of small posters where Classic runs a
/// row of large ones — and in the cap. Every section here is a shortlist with a way
/// to see the rest, which is the whole change: the layout used to show *all* of
/// Continue Watching, which on a real account is fifty titles and a screen nobody
/// can read.
extension CompactHomeView {

    @ViewBuilder
    func view(for section: HomeSection) -> some View {
        switch section {
        case .spotlight, .recentlyAdded:
            // Deliberately absent. A full-bleed backdrop is the opposite of what
            // this layout is for, and Recently Added is the Hero layout's row —
            // Compact's own wall already opens on the newest thing added.
            EmptyView()

        case .quickLinks:
            HomeNewsLine(text: model.newsLine)
            // Compact trades size for count everywhere else, but it gets the same
            // navigation at the same size as the other two layouts: the row exists
            // because the sidebar no longer opens by default, so a layout without
            // it would be a layout you cannot leave Home from.
            HomeQuickLinks(app: app)

        case .libraries:
            LibraryShelf(
                libraries: model.libraryCards, serverURL: serverURL,
                pipeline: pipeline, onOpen: onOpenLibrary
            )

        case .continueWatching:
            if !model.resume.isEmpty {
                let shown = Array(model.resume.prefix(Self.rowLimit))
                titled(
                    "Continue Watching",
                    subtitle: countText(shown.count, of: model.resume.count),
                    action: model.resume.count > shown.count ? onSeeAllResume : nil
                ) {
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(minimum: 260, maximum: 400), spacing: Theme.Space.md
                        )],
                        spacing: Theme.Space.md
                    ) {
                        ForEach(shown) { entry in
                            NavigationLink(value: DetailRoute.forEntry(entry)) {
                                CompactResumeRow(
                                    entry: entry, serverURL: serverURL, pipeline: pipeline
                                )
                                .modifier(MetadataContextMenu(actions: actions(entry)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        case .genres:
            // The point of the row is that it replaces a sidebar every layout
            // shares, so a layout without it would be missing navigation rather
            // than merely looking different.
            GenreShelf(
                genres: model.genreCards, serverURL: serverURL, pipeline: pipeline
            )

        case .nextUp:
            // Missing from this layout entirely until now, which left the one
            // question a home screen exists to answer — what do I watch next —
            // answerable in two layouts out of three.
            if !model.nextUpEntries.isEmpty {
                posterSection(
                    model.nextUpTitle, all: model.nextUpEntries,
                    action: model.nextUpEntries.count > Self.posterLimit ? onSeeAllNextUp : nil
                )
            }

        case .finishSeason:
            if !model.mergesUpNext, !model.finishSeason.isEmpty {
                posterSection("Finish the season", all: model.finishSeason, action: nil)
            }

        case .becauseYouWatched:
            if let because = model.becauseYouWatched {
                posterSection(because.title, all: because.entries, action: nil)
            }
        case .continueSeries:
            if !model.mergesUpNext, !model.continueSeries.isEmpty {
                posterSection("Continue the series", all: model.continueSeries, action: nil)
            }

        case .forgotten:
            if !model.forgotten.isEmpty {
                posterSection("Forgotten", all: model.forgotten, action: nil)
            }

        case .topFilms:
            if !model.topFilms.isEmpty { posterSection("Top 10 Films", all: model.topFilms) }
        case .topSeries:
            if !model.topSeries.isEmpty { posterSection("Top 10 Series", all: model.topSeries) }
        case .topAnime:
            if !model.topAnime.isEmpty { posterSection("Top 10 Anime", all: model.topAnime) }

        case .latest(let libraryId):
            if let shelf = model.libraryShelves.first(where: { $0.library.id == libraryId }),
               !shelf.entries.isEmpty {
                posterSection(
                    "Latest \(shelf.library.name)", all: shelf.entries,
                    action: { onSeeAllLatest(shelf.library) }
                )
            }
        }
    }

    /// The whole library, paged as you scroll. Compact's reason to exist, and the
    /// only section here that is not a shortlist.
    var wall: some View {
        titled(
            "Library",
            subtitle: model.wallTotal > 0 ? "\(model.wallTotal) items" : nil,
            action: nil
        ) {
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(model.wallEntries) { entry in
                    NavigationLink(value: DetailRoute.forEntry(entry)) {
                        PosterCard(
                            entry: entry, serverURL: serverURL,
                            pipeline: pipeline, width: 140,
                            metadata: actions(entry)
                        )
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreIfNeeded(currentItem: entry) }
                }
            }
        }
    }

    /// A capped grid of posters with a See All when there is more behind it.
    func posterSection(
        _ title: String, all: [LibraryEntry], action: (() -> Void)? = nil
    ) -> some View {
        let shown = Array(all.prefix(Self.posterLimit))
        return titled(
            title,
            subtitle: countText(shown.count, of: all.count),
            action: all.count > shown.count ? action : nil
        ) {
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(shown) { entry in
                    NavigationLink(value: DetailRoute.forEntry(entry)) {
                        PosterCard(
                            entry: entry, serverURL: serverURL,
                            pipeline: pipeline, width: 140,
                            metadata: actions(entry)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "12 of 47", and nothing at all when the section is showing everything —
    /// a count that always appears stops being information.
    func countText(_ shown: Int, of total: Int) -> String? {
        total > shown ? "\(shown) of \(total)" : nil
    }

    /// One titled block: the shelf header every layout uses, then the content,
    /// inset to the same margin as everything else on the screen.
    func titled<Content: View>(
        _ title: String,
        subtitle: String?,
        action: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ShelfTitleCard(title: title, subtitle: subtitle, action: action)
            content()
                .padding(.horizontal, Theme.Space.shelfInset)
        }
    }
}
