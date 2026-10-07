import SwiftUI
import LumiereKit

/// Everything starred, across every library.
///
/// Reads straight from the cache: favourites are watch state, which the sync
/// already keeps current, so this needs no server call of its own and works
/// offline like the rest of browsing.
struct FavouritesView: View {
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    /// For the actions a tile carries — unstarring from here especially, which is
    /// the one place someone always wants it and the only grid that never had it.
    var app: AppModel?

    /// The item whose artwork is being chosen or removed. Was missing here, which
    /// is why the menu command did nothing on this screen.
    /// The collection a deletion has been asked for, held while it is confirmed.
    @State private var deleteCollectionTarget: LibraryEntry?
    /// The shared right-click menu. See `EntryActionState`.
    @State private var entryActions = EntryActionState()
    @State private var shelfFilter = ""
    @State private var selection = BatchSelection()
    @State private var batchPlaylistIds: [String] = []
    @State private var entries: [LibraryEntry] = []
    /// The sidebar's library order, so the sections below agree with it.
    @State private var libraryOrder: [(id: String, name: String)] = []
    @State private var total = 0
    @State private var isLoadingPage = false
    private let pageSize = 120
    @State private var isLoading = true

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: Theme.Space.lg, alignment: .top)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                empty
            } else {
                grid
            }
        }
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it.
        .task { await load() }
        // Starring something elsewhere puts it on this page, so an id we do not
        // already hold means reload. One we do hold is refreshed where it sits,
        // which keeps the reader's place in a grid that pages.
        .onLibraryChange { change in
            if let id = change.itemId, entries.contains(where: { $0.id == id }) {
                await refreshRow(id: id)
            } else {
                await load()
            }
        }
    }

    private var visibleEntries: [LibraryEntry] {
        let needle = shelfFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.item.name.lowercased().contains(needle)
                || ($0.item.seriesName?.lowercased().contains(needle) ?? false)
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack {
                ShelfSearchField(
                    text: $shelfFilter,
                    placeholder: "Filter favourites",
                    matchCount: visibleEntries.count,
                    // Says how far in you are while there is more behind it.
                    totalCount: shelfFilter.isEmpty && entries.count < total ? total : nil
                )
                Spacer()
                Button { selection.isActive ? selection.end() : selection.begin() } label: {
                    Image(systemName: selection.isActive
                          ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection.isActive
                                 ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .labelledHelp("Select several and act on all of them")
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.top, Theme.Space.md)

            ScrollViewReader { proxy in
                gridBody
                    // Overlaid, so the poster wall is the same width with the rail
                    // as without it.
                    .overlay(alignment: .trailing) {
                        if visibleEntries.count > 30 {
                            AlphabetRail(
                                destinations: AlphabetIndex.firstIds(
                                    in: visibleEntries,
                                    id: { $0.id },
                                    sortKey: { $0.item.sortName },
                                    name: { $0.item.name }
                                ),
                                proxy: proxy
                            )
                        }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selection.isActive {
                BatchActionBar(
                    selection: selection,
                    totalVisible: visibleEntries.count,
                    onSelectAll: { selection.selectAll(visibleEntries.map(\.id)) },
                    // Unstar, not star: everything here is already a favourite, so
                    // the only useful bulk action on this shelf is removal.
                    onFavourite: { await batchUnfavourite() },
                    onMarkWatched: { await batchWatched($0) },
                    onAddToCollection: nil,
                    onAddToPlaylist: { batchPlaylistIds = Array(selection.ids) }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(Theme.Motion.transition, value: selection.isActive)
        .entryActions(entryActions, in: actionContext)
        .collectionDeleteConfirm(
            target: $deleteCollectionTarget, repository: repository, app: app
        ) {
            await load()
        }
        .sheet(isPresented: Binding(
            get: { !batchPlaylistIds.isEmpty },
            set: { if !$0 { batchPlaylistIds = [] } }
        )) {
            AddToPlaylistSheet(
                itemIds: batchPlaylistIds,
                itemName: "\(batchPlaylistIds.count) titles",
                repository: repository,
                onDone: { batchPlaylistIds = [] }
            )
        }
    }

    private func batchUnfavourite() async {
        await selection.run { id in
            guard let app else { return false }
            return await app.toggleFavourite(itemId: id, isFavourite: true)
        }
        await load()
    }

    private func batchWatched(_ played: Bool) async {
        await selection.run { await repository.setPlayed(itemId: $0, played: played) }
        await load()
    }

    /// One block per library, in the sidebar's order. See `LibraryGrouping`.
    private var sections: [LibraryGrouping.Section] {
        LibraryGrouping.sections(entries: visibleEntries, order: libraryOrder)
    }

    private var gridBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                ForEach(sections) { section in
                    // Only when there is more than one: a heading over the single
                    // group it describes is a label saying what you can already see.
                    if sections.count > 1 {
                        ShelfTitleCard(
                            title: section.name,
                            subtitle: "\(section.entries.count) starred"
                        )
                    }
                    grid(section.entries)
                }
            }
            .padding(.vertical, Theme.Space.xl)
        }
    }

    private func grid(_ rows: [LibraryEntry]) -> some View {
        Group {
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(rows) { entry in
                    Group {
                        if selection.isActive {
                            Button { selection.toggle(entry.id) } label: {
                                PosterCard(
                                    entry: entry, serverURL: serverURL, pipeline: pipeline
                                )
                                .overlay {
                                    SelectionOverlay(isSelected: selection.contains(entry.id))
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: DetailRoute.forEntry(entry)) {
                                PosterCard(
                                    entry: entry, serverURL: serverURL, pipeline: pipeline,
                                    metadata: actions(for: entry)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(entry.id)
                    .task { await loadMoreIfNeeded(entry) }
                }
            }
            .padding(.horizontal, Theme.Space.xxl)
        }
    }

    /// The shared menu, plus the two commands only this shelf can honour.
    ///
    /// It used to build its own, three commands short — no Identify, no Edit, no
    /// Collections — so a wrongly-scraped favourite was one of the few tiles in the
    /// app you had to leave the page to fix. See `EntryActionState`.
    private func actions(for entry: LibraryEntry) -> MetadataActions? {
        guard var actions = entryActions.actions(for: entry, in: actionContext) else {
            return nil
        }
        actions.beginSelection = { selection.begin(with: entry.id) }
        actions.deleteCollection = entry.item.itemType == .boxSet
            ? { deleteCollectionTarget = entry } : nil
        return actions
    }

    private var actionContext: EntryActionContext {
        EntryActionContext(app: app, repository: repository, refreshRow: refreshRow)
    }

    /// Re-reads one row in place after a menu command writes to the server.
    ///
    /// Unstarring is the exception and reloads instead: the row stops belonging on
    /// this shelf at all, so refreshing it in place would leave a tile that is no
    /// longer a favourite sitting in a list of favourites.
    private func refreshRow(id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let fresh = (try? await repository.entriesById([id]))?.first
        else { return }
        if fresh.userData?.isFavorite == false {
            await load()
        } else {
            entries[index] = fresh
        }
    }


    /// Pulls the next window in as the end of the grid comes into view.
    ///
    /// Suspended while a filter is typed: the filter runs over what is loaded, so
    /// paging under it would append rows the filter then hides, which reads as the
    /// list loading forever and finding nothing.
    private func loadMoreIfNeeded(_ entry: LibraryEntry) async {
        guard shelfFilter.isEmpty, entries.count < total, !isLoadingPage,
              let index = entries.firstIndex(where: { $0.id == entry.id }),
              index >= entries.count - 24 else { return }

        isLoadingPage = true
        defer { isLoadingPage = false }
        let page = (try? await repository.favouriteEntries(
            limit: pageSize, offset: entries.count
        )) ?? []
        entries.append(contentsOf: page)
        if page.isEmpty { total = entries.count }
    }

    private func load() async {
        isLoading = true
        // Once per load, for the section order. Cheap — it is the sidebar's own list.
        if libraryOrder.isEmpty {
            // The home screen's order, not the server's — see `LibraryOrdering`.
            libraryOrder = LibraryOrdering
                .sorted((try? await repository.libraries()) ?? [], id: \.id)
                .map { (id: $0.id, name: $0.name) }
        }
        // Explicit and large. The default was 60, with no pagination, no count and
        // an A–Z rail implying a browsable whole — so someone with 300 starred anime
        // saw 60 and had no way to know the rest existed. A favourites list is
        // bounded by how many things a person has starred, so the honest fix is to
        // fetch them rather than to page.
        // Paged, not a blanket ceiling.
        //
        // The limit went from 60 to 2,000 to stop the list truncating silently,
        // which fixed the honesty and not the cost: every row it fetched became a
        // poster decoded into the image cache. A window plus a count says the same
        // true thing without holding a thousand pictures nobody has scrolled to.
        total = (try? await repository.favouriteCount()) ?? 0
        entries = (try? await repository.favouriteEntries(limit: pageSize)) ?? []
        isLoading = false
    }
}
