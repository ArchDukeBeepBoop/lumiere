import SwiftUI
import LumiereKit

/// Routes to the full Next Up list. No payload — there is one such list.
struct NextUpRoute: Hashable {}

/// The next unwatched episode of everything in progress, grouped by library.
///
/// The same page as `ResumeBrowseView`, for the row beside it, and deliberately so:
/// Continue Watching and Next Up answer one question between them — what was I in
/// the middle of — and having one of them expand to a grid while the other stopped
/// at twelve tiles behind a horizontal scroll made the pair inconsistent for no
/// reason anybody chose.
///
/// Posters rather than the wide cards next door. Continue Watching shows stills with
/// a progress bar because how far in you are is the point of it; nothing here has
/// been started, so there is no progress to draw and the poster is the better tile.
struct NextUpBrowseView: View {
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL

    @Environment(AppModel.self) private var app: AppModel?
    @State private var entries: [LibraryEntry] = []
    @State private var isLoading = true
    @State private var entryActions = EntryActionState()
    /// The sidebar's library order, so the blocks agree with it.
    @State private var libraryOrder: [(id: String, name: String)] = []

    /// Everything, not a page. See `ResumeBrowseView.limit` — bounded by how many
    /// shows one person is partway through, which is a human number.
    static let limit = 500

    /// Long enough for a slow answer, short enough that an unreachable server does
    /// not hold an empty page for URLSession's own twenty seconds.
    ///
    /// Longer than the home shelf's four, because the two are being asked different
    /// questions. There the row is one of fifteen and the rest must not wait for it;
    /// here it is the whole page, and returning empty is indistinguishable from
    /// having nothing to watch.
    private static let timeout: TimeInterval = 10

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: Theme.Art.shelfPosterWidth),
            spacing: Theme.Space.tileGap,
            alignment: .top
        )]
    }

    /// One block per library, in the sidebar's order. See `LibraryGrouping`.
    private var sections: [LibraryGrouping.Section] {
        LibraryGrouping.sections(entries: entries, order: libraryOrder)
    }

    private var actionContext: EntryActionContext {
        EntryActionContext(app: app, repository: repository, refreshRow: refreshRow)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.lg) {
                ShelfTitleCard(
                    title: "Next Up",
                    subtitle: entries.isEmpty ? nil : countText
                )

                if entries.isEmpty, !isLoading {
                    empty
                } else {
                    ForEach(sections) { section in
                        // Only when there is more than one: a heading over the single
                        // group it describes is a label saying what you can see.
                        if sections.count > 1 {
                            ShelfTitleCard(
                                title: section.name,
                                subtitle: "\(section.entries.count) waiting"
                            )
                        }
                        grid(section.entries)
                    }
                }
            }
            .padding(.vertical, Theme.Space.xl)
        }
        .polishedScrolling()
        .discreetNavigationTitle("Next Up")
        .entryActions(entryActions, in: actionContext)
        .task { await load() }
        // A watch-state write elsewhere can add or remove a row here, not just
        // change one: finishing something takes it off this list. So an id we
        // already show is refreshed in place — keeping the reader's position —
        // and an id we do not is a reload, because it may now belong.
        .onLibraryChange { change in
            if let id = change.itemId, entries.contains(where: { $0.id == id }) {
                await refreshRow(id: id)
            } else {
                await load()
            }
        }
    }

    private func grid(_ rows: [LibraryEntry]) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
            ForEach(rows) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    PosterCard(
                        entry: entry, serverURL: serverURL, pipeline: pipeline,
                        width: Theme.Art.shelfPosterWidth,
                        metadata: entryActions.actions(for: entry, in: actionContext)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    private var countText: String {
        entries.count == 1 ? "1 episode waiting" : "\(entries.count) episodes waiting"
    }

    /// Re-reads one row after a menu command writes to the server.
    ///
    /// Marking the episode watched takes it off this list — that is what Next Up
    /// means — so that case removes the tile rather than refreshing it in place.
    /// The *series* then has a different next episode, but finding out costs another
    /// round trip to the server; it arrives the next time the page is opened, which
    /// is the same bargain the shelf makes.
    private func refreshRow(id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let fresh = (try? await repository.entriesById([id]))?.first
        else { return }
        if fresh.isPlayed {
            entries.removeAll { $0.id == id }
        } else {
            entries[index] = fresh
        }
    }

    private var empty: some View {
        EmptyStateView(reason: .empty(
            icon: "text.append",
            title: "Nothing waiting",
            detail: "Finish an episode of a series and the next one appears here."
        ))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // Once per load, for the section order. Cheap — it is the sidebar's own list.
        if libraryOrder.isEmpty {
            // The home screen's order, not the server's — see `LibraryOrdering`.
            libraryOrder = LibraryOrdering
                .sorted((try? await repository.libraries()) ?? [], id: \.id)
                .map { (id: $0.id, name: $0.name) }
        }
        let hidden = (try? await repository.hiddenShelfIds()) ?? []
        // From the server, like the shelf: "next" depends on watch state across
        // every device, not on what this cache happens to know.
        entries = (await Timeout.run(seconds: Self.timeout) {
            (try? await repository.nextUpEntries(limit: Self.limit)) ?? []
        } ?? []).filter { !hidden.contains($0.id) }
    }
}
