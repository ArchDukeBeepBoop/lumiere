import SwiftUI
import LumiereKit

/// Where "See All" on a Latest shelf goes.
///
/// A value on the shared navigation stack, like `GenreRoute`, so it pushes on top of
/// Home with a back button rather than replacing the section.
struct LatestRoute: Hashable {
    let libraryId: String
    let libraryName: String
}

/// The fifty most recent additions to one library.
///
/// See All used to open the whole library — the same destination as picking the
/// library itself — which made it a duplicate of something already on screen and
/// lost the one thing the shelf was about. A shelf called "Latest Anime" showing
/// twenty tiles should expand into *more of those*, in the same order, not into
/// 24,000 titles sorted by name.
///
/// Fifty rather than a paging wall, and the cap is the feature: "recent" stops
/// meaning anything a few screens down, and a fixed answer needs no paging, no
/// scroll restoration and no empty-page edge cases. Everything past it is what the
/// library grid is for, and the header says so.
struct LatestBrowseView: View {
    let libraryId: String
    let libraryName: String
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL

    @Environment(AppModel.self) private var app: AppModel?
    @State private var entries: [LibraryEntry] = []
    @State private var isLoading = true

    /// What a shelf's See All promises.
    static let limit = 50

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: Theme.Art.shelfPosterWidth),
            spacing: Theme.Space.tileGap,
            alignment: .top
        )]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.lg) {
                ShelfTitleCard(
                    title: "Latest \(libraryName)",
                    subtitle: entries.isEmpty ? nil : "\(entries.count) most recent"
                )

                if entries.isEmpty, !isLoading {
                    empty
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                        ForEach(entries) { entry in
                            NavigationLink(value: DetailRoute.forEntry(entry)) {
                                PosterCard(
                                    entry: entry, serverURL: serverURL,
                                    pipeline: pipeline, width: Theme.Art.shelfPosterWidth,
                                    metadata: entryActions.actions(for: entry, in: actionContext)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Space.shelfInset)
                }
            }
            .padding(.vertical, Theme.Space.xl)
        }
        .polishedScrolling()
        .discreetNavigationTitle("Latest \(libraryName)")
        .entryActions(entryActions, in: actionContext)
        .task { await load() }
        // Only a row we already show. Watch state does not decide what belongs
        // here — the date added does — so an unknown id is not this page's
        // business, and reloading for one would cost the reader their place in a
        // grid for a change they cannot see.
        .onLibraryChange { change in
            // A sync brought new rows in; one row cannot be refreshed into
            // existence. Everything else stays a single-row update, which is
            // what keeps the reader's place while a tick changes.
            guard let id = change.itemId else { return await load() }
            await refreshRow(id: id)
        }
    }

/// The shared right-click menu. See `EntryActionState`.
    @State private var entryActions = EntryActionState()

    private var actionContext: EntryActionContext {
        EntryActionContext(app: app, repository: repository, refreshRow: refreshRow)
    }

    /// Re-reads one row in place after a menu command writes to the server.
    private func refreshRow(id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let fresh = (try? await repository.entriesById([id]))?.first
        else { return }
        entries[index] = fresh
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Palette.textDisabled)
            Text("Nothing added to \(libraryName) yet")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxxl)
    }

    private func load() async {
        guard entries.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        // The shelf's own loader, asked for more. Same types, same ranking, same
        // folding of a season's worth of episodes into one tile — so this is
        // literally the shelf continued rather than a second idea of "latest".
        entries = await HomeModel.latestTiles(
            repository: repository, libraryId: libraryId,
            hidden: (try? await repository.hiddenShelfIds()) ?? [],
            target: Self.limit
        )
    }
}
