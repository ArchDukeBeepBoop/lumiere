import SwiftUI
import LumiereKit

/// Browses a library one level at a time, straight from the server.
///
/// For music and playlists, which `syncLibrary` deliberately skips: recursing a music
/// library pulls every track, which is unbounded work and would leave tens of
/// thousands of cached rows nothing ever browses. So nothing about them is in the
/// local cache, and the grid and folder browsers — both of which read only cached
/// rows — show them as empty. This fetches one level per screen instead, as you
/// navigate: artists, then albums, then tracks; or a playlist, then its contents.
///
/// Playlists are mixed by nature — a Jellyfin playlist can hold tracks and videos
/// together — so this makes no assumption about what it is listing beyond whether
/// each row can be opened or played.
struct ServerBrowserView: View {
    let libraryId: String
    let title: String
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    let onPlay: (String) -> Void
    /// Hands a whole list plus a starting index to the music queue, so clicking one
    /// track queues the rest of what is on screen behind it — which is what "play
    /// this song" means inside an album.
    var onPlayAudio: (([LibraryEntry], Int) -> Void)?
    /// "music" or "playlists" — decides whether the scope picker appears and whether
    /// a flat list of episodes gets folded up under its series.
    var collectionType: String?
    /// For the actions that reach past this view: the music queue, and a metadata
    /// refresh on the server. Optional so previews and tests can leave it out.
    var app: AppModel?

    /// Where you are, and what each level *is*.
    ///
    /// The kind is carried because an artist is not just another folder: it gets a
    /// header of its own. Without it the view would have to guess from the scope,
    /// which is wrong the moment you reach an artist from anywhere but the Artists
    /// tab — from a search result, or by stepping up out of one of their albums.
    @State var path: [(id: String, name: String, kind: JellyfinItem.ItemType?)] = []

    /// The artist whose page this is, if it is one.
    var currentArtist: (id: String, name: String)? {
        guard let last = path.last, last.kind == .musicArtist else { return nil }
        return (last.id, last.name)
    }
    @State var entries: [LibraryEntry] = []
    // Not private: the paging lives in ServerBrowserView+Paging.swift to keep this
    // file under the line limit, and Swift's `private` is file-scoped.
    @State var isLoading = true
    /// How many the server says are in this listing, against how many are loaded.
    @State var total = 0
    @State var isLoadingPage = false
    /// Which generation owns the page currently in flight. See `loadPage`.
    @State var loadingGeneration = -1
    /// Bumped by every load, so a page still in flight can tell it is stale — a
    /// folder change or a scope switch must not have the previous screen's rows
    /// appended to it.
    @State var generation = 0
    let pageSize = 200
    // Not private: the delete path in ServerBrowserView+Music.swift clears it.
    @State var loadFailed = false
    @State var scope: Scope = .albums
    /// How the track list is ordered, and which way. Server-side — see `TrackSort`.
    @State var trackSort: TrackSort = .title
    @State var trackSortAscending = true
    /// The rows last seen for a screen, keyed the way `reloadKey` keys one.
    ///
    /// Nothing about a music library is in the local cache — every screen is a live
    /// request, by design — so stepping into an album and back, or flicking between
    /// Albums and Artists, paid a full server round trip each time and showed a
    /// spinner over a list the app had displayed seconds earlier. These are the rows
    /// it already had: they go back on screen immediately and the request that
    /// refreshes them runs behind them.
    ///
    /// Bounded, and small. A page is 200 rows and this is a browsing aid, not a
    /// cache — six screens is deep enough to cover stepping into an album and back
    /// out through two levels, and shallow enough that nobody has to think about it.
    @State var recentPages: [String: [LibraryEntry]] = [:]
    @State var recentOrder: [String] = []
    /// Series rows the user has opened, inside a playlist.
    @State var expandedSeries: Set<String> = []
    /// What an Add to Playlist sheet is currently about.
    @State var playlistTarget: LibraryEntry?
    /// What a Choose Artwork sheet is currently about.
    @State var artworkTarget: LibraryEntry?
    /// The album or artist whose metadata "Replace…" is about to overwrite.
    ///
    /// This menu fired that command straight off the click while the shared
    /// film-and-series menu asked first, so the same destructive act had two
    /// different safety levels depending on which shelf you were standing on.
    @State var replaceTarget: LibraryEntry?
    /// A track, album or artist about to leave the library. See `RemovalTarget`.
    @State var removalTarget: RemovalTarget?
    /// Optimistic favourite state, so a star responds to the click rather than to
    /// the round trip. Reconciled by the next load.
    @State var favouriteOverrides: [String: Bool] = [:]
    /// item id → PlaylistItemId, for the rows of the playlist currently open. Only
    /// this map can remove anything: the track's own id is ambiguous in a playlist.
    @State var playlistEntryIds: [String: String] = [:]
    /// Apple Music's edit mode. Off by default because a list you can accidentally
    /// delete from is a worse list to browse.
    @State var isEditingPlaylist = false
    /// The playlist a delete has been asked for, held while it is confirmed.
    ///
    /// Its own id-and-name pair rather than a `LibraryEntry`, because the playlist
    /// being browsed is never in `entries` — those are its *tracks*. Only the
    /// breadcrumb knows what you are inside of.
    @State var deleteTarget: PlaylistTarget?
    @State var selection = BatchSelection()
    @State var batchPlaylistIds: [String] = []
    /// The track whose tags are being edited.
    @State var trackEditTarget: LibraryEntry?

    @Environment(\.displayScale) var scale

    var currentId: String { path.last?.id ?? libraryId }
    /// The genre being browsed, when the last step into this path was one.
    ///
    /// Named rather than identified because that is all a genre is on the server:
    /// a value on a track. See `LibraryRepository.musicGenrePage`.
    var openGenre: String? {
        guard let last = path.last, last.kind == .musicGenre else { return nil }
        return last.name
    }
    private var isMusic: Bool { collectionType == "music" }
    var isPlaylist: Bool { collectionType == "playlists" }
    /// Whether right-clicking a row should offer the music menu at all. A folder
    /// library of loose video files goes through this same view, and "Add to
    /// Favourites / Add to Playlist" is the wrong menu for a video file here.
    var offersMusicActions: Bool { isMusic || isPlaylist }
    /// The scope picker only applies at the library's own root. Once you have opened
    /// an album, "show me all artists" is no longer a statement about where you are.
    var showsScopePicker: Bool { isMusic && path.isEmpty }
    /// What a reload depends on: where you are, and which scope is showing.
    /// How many screens of rows to keep. See `recentPages`.
    static let recentPageLimit = 6

    // Not private: the paging in ServerBrowserView+Paging.swift reads it.
    var reloadKey: String {
        "\(currentId)#\(scope.rawValue)#\(trackSort.rawValue)#\(trackSortAscending)"
    }
    /// Covers are the point for albums and artists. Tracks stay a list — a wall of
    /// identical album art repeated once per song says nothing.
    // Not private: the body that reads it is in ServerBrowserView+Content.swift.
    var usesTileGrid: Bool {
        // An artist's page too, not only the library root. Their albums were falling
        // through to the plain list, so opening an artist produced a column of names
        // — the same view a folder of loose files gets — where the whole point of an
        // artist page is their covers.
        if currentArtist != nil { return true }
        return showsScopePicker && (scope == .albums || scope == .artists)
    }

    var body: some View { withPlaylistDelete(withBatch(core)) }

    private var core: some View {
        VStack(spacing: 0) {
            breadcrumb
            if showsScopePicker { scopePicker }
            Divider()
            content
        }
        .background(Theme.Palette.canvas)
        // One task keyed on both, not one task each. Two of them fired together on
        // first appearance and cancelled each other out: the first `load` bumped
        // the generation and started a request; the second bumped it again and then
        // hit `loadPage`'s `isLoadingPage` guard and returned immediately; and when
        // the first request finally answered, its generation was stale, so its rows
        // were discarded as belonging to a screen the user had left. Nothing
        // arrived, and the grid stayed empty until something changed the scope —
        // which is exactly the "click a different tab and then it loads" report.
        .task(id: reloadKey) { await load() }
        // Makes good on what the offline empty state promises. This screen holds
        // nothing cached, so coming back online is the only thing that can fill it —
        // and without this it would stay empty until the user navigated away and
        // back, which reads as the reconnect not having worked.
        .onChange(of: app?.isOffline ?? false) { _, isOffline in
            if !isOffline, entries.isEmpty { Task { await load() } }
        }
        .sheet(item: $trackEditTarget) { target in
            if let client = app?.client {
                EditTrackSheet(
                    itemId: target.id, repository: repository, client: client,
                    onDone: { changed in
                        trackEditTarget = nil
                        if changed { Task { await load() } }
                    }
                )
            }
        }
        .sheet(item: $playlistTarget) { target in
            AddToPlaylistSheet(
                itemIds: [target.id],
                itemName: target.item.name,
                repository: repository,
                onDone: { playlistTarget = nil }
            )
        }
        .sheet(item: $artworkTarget) { target in
            if let client = app?.client {
                ArtworkPickerSheet(itemId: target.id, client: client) { changed in
                    artworkTarget = nil
                    if changed { Task { await refreshMetadata(target, replaceEverything: false) } }
                }
            }
        }
        .removalConfirmations(target: $removalTarget) { target in
            guard let app, let repository = app.repository else { return }
            if target.permanent {
                do {
                    try await repository.deleteToTrash(itemId: target.entry.id)
                    app.reportTrashed("\(target.entry.item.name)")
                } catch {
                    app.report(ConnectionState.message(for: error))
                }
            } else if await repository.removeFromLibrary(itemId: target.entry.id) {
                app.report("\(target.entry.item.name) removed. Restore it from Settings › Library.")
            }
            await load()
        }
        // The same question the film and series menu asks, in the same words.
        // See `replaceTarget`.
        .confirmationDialog(
            "Replace \(replaceTarget?.item.name ?? "")'s metadata and artwork?",
            isPresented: Binding(
                get: { replaceTarget != nil },
                set: { if !$0 { replaceTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                if let target = replaceTarget {
                    Task { await refreshMetadata(target, replaceEverything: true) }
                }
                replaceTarget = nil
            }
            Button("Cancel", role: .cancel) { replaceTarget = nil }
        } message: {
            Text("Re-scrapes from your server's providers and overwrites what "
               + "is there now, including titles and covers you corrected by "
               + "hand. Locked fields are kept.")
        }
    }

    // MARK: - Path

    // MARK: - Contents

    /// Attaches the music menu where it applies, and nothing where it does not.
    @ViewBuilder
    func menued(_ content: some View, for entry: LibraryEntry) -> some View {
        if offersMusicActions {
            content.contextMenu { musicMenu(for: entry) }
        } else {
            content
        }
    }

}

extension ServerBrowserView {
    /// Playlists fold their episodes under the shows they came from; everything else
    /// lists as-is. The rule itself lives in `PlaylistGrouping` so it can be tested
    /// without a server or a view.
    var rows: [PlaylistRow] {
        isPlaylist ? PlaylistGrouping.rows(for: entries) : entries.map(PlaylistRow.item)
    }
}
