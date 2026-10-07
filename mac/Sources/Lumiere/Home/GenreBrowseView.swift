import SwiftUI
import LumiereKit

/// Where a genre card goes.
///
/// A value on the shared navigation stack rather than a `Route` case, so a genre
/// pushes on top of Home with a back button — the same way a poster does — instead
/// of replacing the section and stranding you. That also keeps the sidebar
/// selection on Home, which is where you still are.
struct GenreRoute: Hashable {
    let name: String
    /// A studio rather than a genre — "Bones", "Studio Ghibli" — opened from
    /// search. The same wall, filtered by studio instead.
    var isStudio = false
}

/// Everything in one genre, as a paging poster wall.
///
/// Deliberately its own screen rather than a reuse of `LibraryGridView`: that view
/// is a library — it owns sorting, batch selection, the alphabet rail and a dozen
/// sheets, all keyed to a library id this has no equivalent for. What a genre needs
/// is the grid and nothing else.
struct GenreBrowseView: View {
    let genre: String
    /// Set when the wall is a studio's. See `GenreRoute.isStudio`.
    var isStudio = false
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL

    @Environment(AppModel.self) private var app: AppModel?
    /// The shelf on show, by `LibraryGrouping.Section.id`. Nil for all of them.
    ///
    /// Not persisted: it is a decision about this visit to this genre, and coming
    /// back to "Action" a week later filtered to a library you have forgotten
    /// choosing reads as a genre that has lost most of its titles.
    @State private var shelfFilter: String?
    @State private var entries: [LibraryEntry] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var offset = 0
    @State private var isLoadingPage = false
    /// The sidebar's library order, so the sections agree with it.
    @State private var libraryOrder: [(id: String, name: String)] = []

    /// The same window-that-grows the library grid and the compact wall use. A
    /// genre can be most of a large library, so this must never be "fetch it all".
    private let pageSize = 60

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
                header

                if entries.isEmpty && !isLoading {
                    empty
                } else {
                    // One block per library. A genre gathers from everywhere, so
                    // "Action" was a wall with a film, an anime episode and a home
                    // video beside each other and nothing saying so. See
                    // `LibraryGrouping`.
                    ForEach(sections) { section in
                        if sections.count > 1 {
                            ShelfTitleCard(
                                title: section.name,
                                subtitle: "\(section.entries.count) in \(genre)"
                            )
                        }
                        LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                            ForEach(section.entries) { entry in
                                NavigationLink(value: DetailRoute.forEntry(entry)) {
                                    PosterCard(
                                        entry: entry,
                                        serverURL: serverURL,
                                        pipeline: pipeline,
                                        width: Theme.Art.shelfPosterWidth,
                                        metadata: entryActions.actions(
                                            for: entry, in: actionContext
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .task { await loadMoreIfNeeded(currentItem: entry) }
                            }
                        }
                        .padding(.horizontal, Theme.Space.shelfInset)
                    }
                }

                if isLoadingPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
            }
            .padding(.vertical, Theme.Space.xl)
        }
        .polishedScrolling()
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it.
        .discreetNavigationTitle(genre)
        .entryActions(entryActions, in: actionContext)
        .task { await reload() }
        // Row only. What belongs to a genre does not change because something was
        // watched, and this grid pages — reloading it for a tick the reader
        // cannot see would cost them their position for nothing.
        .onLibraryChange { change in
            // A sync brought new rows in; one row cannot be refreshed into
            // existence. Everything else stays a single-row update, which is
            // what keeps the reader's place while a tick changes.
            guard let id = change.itemId else { return await reload() }
            await refreshRow(id: id)
        }
    }

    /// The same title card the shelf this was clicked from uses, so arriving here
    /// reads as having followed the card rather than as a different app.
    /// Every shelf this genre reaches, before the filter.
    private var allSections: [LibraryGrouping.Section] {
        LibraryGrouping.sections(entries: entries, order: libraryOrder)
    }

    /// What is on screen: one shelf, or all of them.
    private var sections: [LibraryGrouping.Section] {
        guard let shelfFilter else { return allSections }
        return allSections.filter { $0.id == shelfFilter }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: Theme.Space.md) {
            ShelfTitleCard(title: genre, subtitle: headerSubtitle)
            shelfPicker
        }
    }

    private var headerSubtitle: String? {
        guard total > 0 else { return nil }
        // The filtered count when one shelf is chosen, because "1,204 titles" over a
        // wall of forty is a number about a page you are no longer looking at.
        if shelfFilter != nil {
            let shown = sections.reduce(0) { $0 + $1.entries.count }
            return "\(shown) of \(total) titles"
        }
        return "\(total) titles"
    }

    /// Picks one shelf out of the several a genre gathers from.
    ///
    /// A genre crosses every library — "Action" reaches films, anime and home video
    /// at once — and the headings say which is which but do not help you get to one:
    /// the anime block can be four hundred posters below the films. This narrows the
    /// page to a single shelf.
    ///
    /// Absent when there is nothing to choose between. A picker with one option in it
    /// is a control that cannot do anything, which is worse than no control.
    @ViewBuilder
    private var shelfPicker: some View {
        if allSections.count > 1 {
            Picker("Shelf", selection: $shelfFilter) {
                Text("All shelves").tag(String?.none)
                Divider()
                ForEach(allSections) { section in
                    Text("\(section.name) (\(section.entries.count))")
                        .tag(String?.some(section.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            .padding(.trailing, Theme.Space.shelfInset)
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
            Image(systemName: "square.stack")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Palette.textDisabled)
            Text("Nothing in \(genre) yet")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxxl)
    }

    private func reload() async {
        // Guarded, because `.task` runs again whenever the view is rebuilt and a
        // second pass would append the first page on top of itself.
        guard entries.isEmpty else { return }
        isLoading = true
        if libraryOrder.isEmpty {
            // The home screen's order, not the server's — see `LibraryOrdering`.
            libraryOrder = LibraryOrdering
                .sorted((try? await repository.libraries()) ?? [], id: \.id)
                .map { (id: $0.id, name: $0.name) }
        }
        defer { isLoading = false }
        total = (try? await repository.count(
            types: LibraryRepository.topLevelTypes,
            genre: isStudio ? nil : genre, studio: isStudio ? genre : nil
        )) ?? 0
        offset = 0
        await loadPage()
    }

    private func loadPage() async {
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let page = (try? await repository.entries(
            types: LibraryRepository.topLevelTypes,
            sort: .title,
            limit: pageSize,
            offset: offset,
            genre: isStudio ? nil : genre, studio: isStudio ? genre : nil
        )) ?? []
        entries.append(contentsOf: page)
        offset += page.count
    }

    /// Paged on appearance rather than on a scroll offset, so the loaded window
    /// stays bounded however far down a large genre you go.
    private func loadMoreIfNeeded(currentItem entry: LibraryEntry) async {
        guard entries.count < total else { return }

        // Under a shelf filter the window on screen is a slice of what is loaded, and
        // that slice can sit anywhere in it. Paging on "twelve from the end of
        // `entries`" then never fires — you scroll to the bottom of a filtered shelf,
        // the page below is a library the filter hides, and the genre appears to have
        // run out. Reaching the end of what is *shown* is the signal instead.
        if shelfFilter != nil {
            guard sections.last?.entries.last?.id == entry.id else { return }
            await loadPage()
            return
        }

        guard let index = entries.firstIndex(where: { $0.id == entry.id }),
              index >= entries.count - 12 else { return }
        await loadPage()
    }
}
