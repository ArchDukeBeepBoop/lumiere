import SwiftUI
import LumiereKit

/// Routes to the full Continue Watching list. No payload — there is one such list.
/// The See All page for the two shelves built from unfinished things.
///
/// One view, two questions. Continue Watching is "what was I doing"; Forgotten
/// is "what did I leave" — the same rows, read from opposite ends, with a
/// cut-off between them. The page is the same wide-card wall grouped by
/// library; only the query, the title and the count's noun change.
struct ResumeRoute: Hashable {
    enum Shelf: Hashable {
        case continueWatching
        case forgotten
        /// What was finished, newest first. Reached from Continue Watching.
        case history
    }
    var shelf: Shelf = .continueWatching
}

/// Everything started and not finished, in the order it was last watched.
///
/// The shelf shows twelve, which is the right number for a row you scan on the way
/// past. It is the wrong number for the question "what have I left unfinished" — on
/// this library that is thirty-one titles across five libraries, so the shelf was
/// hiding more than half of them behind a horizontal scroll with no indication that
/// there was more to see.
///
/// Wide cards rather than posters, matching the shelf: these are episodes and
/// part-watched films, and the still with a progress bar under it is what says how
/// far in you are. A grid of posters would throw that away.
struct ResumeBrowseView: View {
    var shelf: ResumeRoute.Shelf = .continueWatching
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL

    @Environment(AppModel.self) private var app: AppModel?
    @State private var entries: [LibraryEntry] = []
    @State private var isLoading = true
    @State private var entryActions = EntryActionState()
    /// The sidebar's library order, so the blocks agree with it.
    @State private var libraryOrder: [(id: String, name: String)] = []

    /// Everything, not a page.
    ///
    /// Continue Watching is bounded by how much you personally started and did not
    /// finish, which is a human number — thirty-one here, and it would take years of
    /// abandoning things to reach a thousand. Paging machinery for that would be
    /// scroll restoration and empty-page handling bought for a list that fits in one
    /// query. The cap exists only so a pathological account cannot ask for
    /// everything at once.
    static let limit = 500

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: Theme.Art.continueCardWidth),
            spacing: Theme.Space.tileGap,
            alignment: .top
        )]
    }

    /// One block per library, in the sidebar's order. See `LibraryGrouping`.
    ///
    /// The shelf is one strip because a strip is what a shelf is. This page is the
    /// whole list, and on this library that is fifty-odd unfinished titles spread
    /// across five libraries — an anime episode, a film and a home video in one
    /// undivided grid, with nothing saying which is which. The same reasoning as
    /// Favourites and the genre pages, which already group.
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
                    title: pageTitle,
                    subtitle: entries.isEmpty ? nil : countText
                )
                if shelf == .continueWatching {
                    NavigationLink(value: ResumeRoute(shelf: .history)) {
                        Text("Watched lately ›")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.Space.shelfInset)
                }

                if entries.isEmpty, !isLoading {
                    empty
                } else {
                    ForEach(sections) { section in
                        // Only when there is more than one: a heading over the single
                        // group it describes is a label saying what you can see.
                        if sections.count > 1 {
                            ShelfTitleCard(
                                title: section.name,
                                subtitle: "\(section.entries.count) \(noun)"
                            )
                        }
                        grid(section.entries)
                    }
                }
            }
            .padding(.vertical, Theme.Space.xl)
        }
        .polishedScrolling()
        .discreetNavigationTitle(pageTitle)
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
                    WideCard(
                        entry: entry, serverURL: serverURL, pipeline: pipeline,
                        width: Theme.Art.continueCardWidth,
                        // The show's art, as on the shelf, so a season's worth of
                        // episodes does not read as a wall of unrelated frame grabs.
                        preferSeriesThumb: true,
                        metadata: entryActions.actions(for: entry, in: actionContext),
                        // See ClassicHomeView.
                        onPlay: { app?.nowPlayingItemId = entry.item.id }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    private var noun: String {
        switch shelf {
        case .forgotten: return "forgotten"
        case .history: return "watched"
        case .continueWatching: return "unfinished"
        }
    }

    private var pageTitle: String {
        switch shelf {
        case .forgotten: return "Forgotten"
        case .history: return "Watched Lately"
        case .continueWatching: return "Continue Watching"
        }
    }

    private var countText: String {
        "\(entries.count) \(noun)"
    }

    /// Re-reads one row after a menu command writes to the server.
    ///
    /// Marking something watched takes it off this list entirely, so that case
    /// reloads rather than refreshing in place — a tile that is no longer unfinished
    /// sitting in a list of unfinished things is worse than a moment's flicker.
    private func refreshRow(id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let fresh = (try? await repository.entriesById([id]))?.first
        else { return }
        if shelf == .history {
            entries[index] = fresh
        } else if fresh.isPlayed || fresh.userData?.playbackPositionTicks ?? 0 == 0 {
            entries.removeAll { $0.id == id }
        } else {
            entries[index] = fresh
        }
    }

    @ViewBuilder
    private var empty: some View {
        if shelf == .history {
            EmptyStateView(reason: .empty(
                icon: "checkmark.circle", title: "Nothing watched yet",
                detail: "What you finish appears here, newest first."))
        } else if shelf == .forgotten {
            EmptyStateView(reason: .empty(
                icon: "clock.arrow.circlepath",
                title: "Nothing forgotten",
                detail: "Anything left part-watched for more than \(SpotlightReason.forgottenAfterDays) "
                      + "days lands here, oldest first — the things Continue Watching "
                      + "has quietly scrolled past."
            ))
        } else {
            EmptyStateView(reason: .empty(
                icon: "play.circle",
                title: "Nothing in progress",
                detail: "Start something and it will appear here, on every device signed "
                      + "into this server."
            ))
        }
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
        let rows: [LibraryEntry]
        switch shelf {
        case .continueWatching:
            rows = (try? await repository.resumeEntries(limit: Self.limit)) ?? []
        case .history:
            rows = (try? await repository.watchedRecently()) ?? []
        case .forgotten:
            // Oldest first, as on the shelf: the point is the thing you have
            // not thought about. See `forgottenEntries`.
            rows = (try? await repository.forgottenEntries(limit: Self.limit)) ?? []
        }
        entries = rows.filter { !hidden.contains($0.id) }
    }
}
