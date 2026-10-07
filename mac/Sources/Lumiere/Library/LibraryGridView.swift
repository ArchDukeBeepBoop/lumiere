import SwiftUI
import LumiereKit

/// A whole library as a paging poster wall.
///
/// The grid never holds the library: it holds a window that grows as you scroll
/// and is capped by how far you have actually scrolled, not by the library size.
/// A 5,000-item library and a 200-item one cost the same at rest.
struct LibraryGridView: View {
    let libraryId: String
    let title: String
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    var app: AppModel?

    // Not private: LibraryGridView+Empty.swift reads these to decide which empty
    // state to draw, and Swift's `private` is file-scoped.
    @State var entries: [LibraryEntry] = []
    // Not private: LibraryGridView+Toolbar.swift draws the controls that read and
    // write these, and Swift's `private` is file-scoped.
    @State var total = 0
    @State var sort: LibraryRepository.Sort = .title
    @State var descending: Bool?
    @State var unwatchedOnly = false
    @State var genre: String?
    /// All, Films, Shows, Collections. See `LibraryTab`.
    @State var tab: LibraryTab = .all
    @State var availableTabs: [LibraryTab] = []
    @State var genres: [String] = []
    /// The studio filter, built the same way and from the same cache as the genre
    /// one above it. Anime and adult are where it matters: the studio is how
    /// those libraries are actually navigated.
    @State var studio: String?
    @State var studios: [String] = []
    @State var isLoading = true
    /// The shared menu's state: the sheets it opens, and nothing else. Replaces
    /// six separate @State properties this view used to keep for itself.
    @State var entryState = EntryActionState()
    @State var isProposingCollections = false
    @State var isDiscoveringCollections = false
    /// The library-wide merged-series sweep. Not per-library: a merge is a property
    /// of a series, and the scan is cheap enough to always cover everything rather
    /// than making where you opened it from change what it finds.
    @State var isScanningMergedSeries = false
    /// Many-at-once. Off until asked for: a grid where a click selects rather than
    /// opens is a different grid, and it must never be the one you land on.
    @State var selection = BatchSelection()
    @State var batchCollectionIds: [String] = []
    @State var batchPlaylistIds: [String] = []
    /// The collection a delete has been asked for, held while it is confirmed.
    @State var deleteCollectionTarget: LibraryEntry?
    @State var shelfFilter = ""
    /// The filter as the query sees it. Empty means unfiltered.
    ///
    /// The filter used to run over the rows already loaded — sixty out of
    /// twenty-four thousand — so typing part of a title matched nothing unless
    /// that title happened to be on the first page. It is a real query now.
    var activeFilter: String? {
        let term = shelfFilter.trimmingCharacters(in: .whitespaces)
        return term.isEmpty ? nil : term
    }
    /// Where each letter starts in the *whole* library, not in the loaded window.
    /// Rebuilt whenever the sort or the genre filter changes what "first" means.
    @State var anchors: [AlphabetAnchor] = []
    @State var filterTask: Task<Void, Never>?
    // Not private: the loading lives in LibraryGridView+Loading.swift to keep
    // this file under the line limit, and Swift's `private` is file-scoped.
    @State var isLoadingPage = false
    /// Which generation owns the page currently in flight. See `loadPage`.
    @State var loadingGeneration = -1
    /// Bumped by every reload, so a page in flight can tell it is stale.
    // Not private: the loading lives in LibraryGridView+Loading.swift to keep
    // this file under the line limit, and Swift's `private` is file-scoped.
    @State var generation = 0
    // Not private: the loading lives in LibraryGridView+Loading.swift to keep
    // this file under the line limit, and Swift's `private` is file-scoped.
    @State var offset = 0
    /// Shared with FolderBrowserView under the same key: one tile size for every
    /// grid, since it is a reading preference rather than something that makes
    /// sense to set differently per library.
    // Not private: the tile-size control lives in LibraryGridView+Empty.swift, and
    // Swift's `private` is file-scoped.
    @AppStorage("gridTileWidth") var tileWidth: Double = Double(Theme.Art.posterWidth)
    /// The slider's live value while it is being dragged. See `tileSizeControl`.
    @State var draftTileWidth: Double = Double(Theme.Art.posterWidth)
    /// Where the arrow keys are. See `GridKeyboard`.
    @State var keyboard = GridKeyboard()
    @FocusState var gridHasFocus: Bool

    let pageSize = 60

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: CGFloat(tileWidth)), spacing: Theme.Space.lg, alignment: .top)]
    }

    var body: some View { withBatchSheets(core) }

    private var core: some View {
        ScrollViewReader { proxy in
            ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                        ForEach(visibleEntries) { entry in
                            tile(entry)
                                .id(entry.id)
                                .task { await loadMoreIfNeeded(currentItem: entry) }
                        }
                    }
                    .padding(Theme.Space.xxl)
                    // The grid's columns are `.adaptive`, so the row width is
                    // the only place the column count exists. Arrow-up and
                    // arrow-down need it.
                    .background {
                        GeometryReader { geometry in
                            Color.clear.onChange(
                                of: geometry.size.width, initial: true
                            ) {
                                keyboard.columns = GridKeyboard.columnCount(
                                    width: geometry.size.width,
                                    tileWidth: CGFloat(tileWidth),
                                    spacing: Theme.Space.lg
                                )
                            }
                        }
                    }

                if isLoadingPage {
                    ProgressView().padding(.bottom, Theme.Space.xxl)
                }
            }
            // An overlay, never a sibling. As an HStack member the rail took real
            // width from the grid, which narrowed every library by twenty-odd
            // points and reflowed the columns — the tiles are the content, and a
            // shortcut past them must not resize them. Floating it also means the
            // layout is identical whether the rail is shown or not.
            .focusable()
            .focusEffectDisabled()
            .focused($gridHasFocus)
            .onMoveCommand { direction in
                let ids = visibleEntries.map(\.id)
                if let landed = keyboard.move(direction, in: ids) {
                    withAnimation(Theme.Motion.hover) {
                        proxy.scrollTo(landed, anchor: .center)
                    }
                    // Arrowing to the end of what is loaded pulls the next page,
                    // so the keyboard can walk the whole library rather than
                    // stopping at the window the mouse happened to load.
                    if let entry = visibleEntries.last, landed == entry.id {
                        Task { await loadMoreIfNeeded(currentItem: entry) }
                    }
                }
            }
            .onKeyPress(.return) {
                guard let id = keyboard.focusedId,
                      let entry = visibleEntries.first(where: { $0.id == id })
                else { return .ignored }
                app?.requestedRoute = DetailRoute.forEntry(entry)
                return .handled
            }
            .onKeyPress(.escape) {
                guard keyboard.focusedId != nil else { return .ignored }
                keyboard.clear()
                return .handled
            }
            .onChange(of: gridHasFocus) {
                // The ring appears when the grid is given focus, not before: a
                // page that opens with a tile already ringed looks as though it
                // made a choice on your behalf.
                if gridHasFocus { keyboard.begin(in: visibleEntries.map(\.id)) }
            }
            .overlay(alignment: .trailing) {
                if showsRail {
                    AlphabetRail(
                        destinations: railDestinations,
                        proxy: proxy,
                        prepare: { await loadThrough(letter: $0) }
                    )
                }
            }
        }
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it.
        // Five sheets in one modifier, shared with every other surface that
        // shows tiles. See `EntryActions+Sheets`.
        .entryActions(entryState, in: entryContext)
        .sheet(isPresented: $isScanningMergedSeries) {
            if let client = app?.client {
                MergedSeriesSheet(
                    repository: repository,
                    client: client,
                    onDone: { changed in
                        isScanningMergedSeries = false
                        if changed { Task { await reload() } }
                    }
                )
            }
        }
        // The movie database's film series, gathered from this room's films.
        .sheet(isPresented: $isDiscoveringCollections) {
            if let app, let client = app.client {
                CollectionSeriesSheet(
                    mode: .discover, client: client, initialQuery: "",
                    privateLibraryIds: app.privateLibraryIds, inRoom: app.isShowingPrivateLibraries
                ) { changed in
                    isDiscoveringCollections = false
                    if changed { Task { await reload() } }
                }
            }
        }
        .sheet(isPresented: $isProposingCollections) {
            RelatedCollectionsSheet(
                libraryId: libraryId,
                libraryName: title,
                repository: repository,
                client: app?.client,
                pipeline: pipeline,
                serverURL: serverURL,
                onDone: { created in
                    isProposingCollections = false
                    // New collections are items in this library, so the grid has to
                    // be re-read to show them.
                    if created { Task { await reload() } }
                }
            )
        }
        .safeAreaInset(edge: .top) { toolbar }
        .safeAreaInset(edge: .bottom) {
            if selection.isActive {
                BatchActionBar(
                    selection: selection,
                    totalVisible: visibleEntries.count,
                    onSelectAll: { selection.selectAll(visibleEntries.map(\.id)) },
                    onFavourite: { await batchFavourite() },
                    onMarkWatched: { await batchWatched($0) },
                    onAddToCollection: { batchCollectionIds = Array(selection.ids) },
                    onAddToPlaylist: { batchPlaylistIds = Array(selection.ids) },
                    onQueueSubtitles: { await batchQueueSubtitles() }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(Theme.Motion.transition, value: selection.isActive)
        .overlay { emptyState }
        // Row only, and this is the page the rule was written for: a library grid
        // pages to forty thousand items, so reloading it because one episode was
        // watched would throw away the reader's place in exchange for a tick they
        // are not looking at. Its own menus already refresh a single row; this is
        // the same refresh, for a write that happened somewhere else.
        .onLibraryChange { change in
            // A sync that wrote to *this* library is the exception to the
            // row-only rule above. New titles cannot be picked up one row at a
            // time — the rows are not there yet — and this is the one moment
            // the reader is watching for what they just asked for, so the place
            // in the list is worth less than the answer.
            if change.libraryId == libraryId {
                Diagnostics.log("[change] grid \(libraryId) reloading")
                await reload()
                return
            }
            guard let id = change.itemId else { return }
            await refreshRow(id: id)
        }
        .task {
            // Through `genreTallies`, which is the only implementation now.
            //
            // There were two, and the other one lied: its doc comment promised "the
            // filter never offers a genre with nothing behind it" while applying
            // none of the filters the grid below it applies — no type restriction,
            // no extras exclusion, no hidden collections, no privacy. On the Anime
            // library that offered nine genres whose grid returns zero rows,
            // "Action" among them, because 8,558 *episodes* carry it and not one
            // series does. Asking the same question one way is the fix.
            genres = ((try? await repository.genreTallies(
                types: LibraryRepository.topLevelTypes, libraryId: libraryId
            )) ?? []).map(\.name).sorted()
            // Asked the same way, so the menu and the grid agree about what is in
            // this library — the mistake documented above for genres.
            studios = ((try? await repository.studioTallies(
                types: LibraryRepository.topLevelTypes, libraryId: libraryId
            )) ?? []).map(\.name).sorted()
            // Which tabs this library has: All, then each kind it holds.
            var tabs: [LibraryTab] = [.all]
            for kind in [LibraryTab.films, .shows, .collections] {
                if ((try? await repository.count(types: kind.types, libraryId: libraryId)) ?? 0) > 0 {
                    tabs.append(kind)
                }
            }
            availableTabs = tabs
            await reload()
        }
        .onChange(of: tab) { Task { await reload() } }
    }

}
