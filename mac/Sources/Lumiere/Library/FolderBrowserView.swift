import SwiftUI
import LumiereKit

/// Browses a library the way it sits on disk.
///
/// For libraries holding loose files rather than matched titles — "3D", "My Videos" —
/// where the metadata grid is the wrong shape: it drops the folders the user organised
/// things into and flattens hundreds of files into one alphabetical wall.
///
/// Its own view rather than a mode flag on `LibraryGridView`, because the two differ
/// in what they *are*: this one has navigation state and a path, and shows every item
/// including the folders and untyped videos the grid deliberately filters out.
struct FolderBrowserView: View {
    let libraryId: String
    let title: String
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    /// Plays an item, optionally one particular file of it.
    ///
    /// The source id matters for the files Jellyfin merged into a neighbour: they
    /// have no item of their own, so playing one means naming the item that swallowed
    /// it *and* which of its files to open. See `ItemVersionRecord`.
    let onPlay: (String, String?) -> Void
    /// Optional so a preview can build one without a session. Present so a video
    /// file can be given a thumbnail generated from its own frames, which needs a
    /// client — and the folder browser is exactly where files with no artwork end up.
    var app: AppModel?

    /// Where we are. The library itself is the root, and each entry is one level down.
    @State var path: [(id: String, name: String)] = []
    @State var entries: [LibraryEntry] = []
    @State var isLoading = true
    /// Distinguishes an empty folder from one whose contents are not cached yet — they
    /// look the same and need different explanations.
    @State var neverSynced = false
    /// Per-folder, and reset on navigation: a filter that survived stepping into a
    /// subfolder would hide most of what you just opened.
    @State var shelfFilter = ""
    @State var selection = BatchSelection()
    /// One folder's listing per parent id, for the column layout. Kept across
    /// navigation on purpose: walking back up a path you already opened should not
    /// re-read every level above you.
    @State var columnCache: [String: [LibraryEntry]] = [:]

    @Environment(\.displayScale) private var scale
    /// Same key as LibraryGridView's tile-size control — one preference for every
    /// grid, not a per-library setting.
    @AppStorage("gridTileWidth") var tileWidth: Double = Double(Theme.Art.posterWidth)
    /// Where the slider's value lives while the thumb is down. See
    /// `tileSizeControl`.
    @State var draftTileWidth: Double = Double(Theme.Art.posterWidth)
    /// The shared menu's state. See `EntryActionState`.
    @State var entryState = EntryActionState()
    /// Portrait or landscape tiles, per library.
    ///
    /// Per library rather than global: a folder of films wants posters, a folder
    /// of clips and home video wants frame grabs.
    @AppStorage("folderTileShape") var tileShapeRaw = ""
    /// Icons, list or columns, remembered per library. See `FolderViewMode`.
    @AppStorage(FolderViewMode.storageKey) var viewModeRaw = ""

    // Not private: the layouts in the +List and +Columns files read it.
    var viewMode: FolderViewMode {
        FolderViewMode.mode(for: libraryId, in: viewModeRaw)
    }

    // Not private: FolderBrowserView+Cells.swift draws with these.
    var isLandscape: Bool {
        tileShapeRaw.split(separator: ",").contains(Substring(libraryId))
    }

    /// The shape a folder tile takes. Files no longer follow it — see `fileCell`.
    ///
    /// Square by default, which is what Finder's icon view is and what these walls
    /// are for. A folder has no artwork to be a shape *of*: the tile is a glyph and a
    /// name, and at 2:3 that glyph floated in the middle of a plate two-thirds of
    /// which was empty — a column of tall grey rectangles standing in for the one
    /// thing on this screen that has nothing to show.
    var tileAspect: CGFloat {
        isLandscape ? Theme.Art.thumbAspect : 1
    }

    /// How wide a video file is drawn, which is the episode still's width.
    ///
    /// These libraries hold loose files with no cover art, so a 2:3 poster over one
    /// was a tall grey rectangle with a filename under it — the shape promised
    /// artwork that does not exist. A 16:9 card is the shape the content actually
    /// is, and `WideCard` draws a titled `GeneratedThumb` when the server has no
    /// still either, so the tile always says what the file is.
    ///
    /// Exactly `DetailMetrics.episodeWidth`, not a fraction of it. It used to be
    /// scaled by the tile slider, so a video file matched an anime episode's still
    /// at one slider position and was a different size everywhere else; these are
    /// the same kind of thing and are drawn the same size. The slider still sizes
    /// the *folder* posters beside them.
    /// One width for every tile in the wall, folder or file.
    ///
    /// Both shapes are the same size now, which is what lets the two grids below
    /// become one. They were split because a single `.adaptive` column has a single
    /// minimum: sized for 360-wide file cards it stranded each folder poster in a
    /// column two and a half times its own width, and sized for posters it wrapped
    /// every file card onto its own row. With files drawn at the folders' width that
    /// conflict is gone, and folders and files sit side by side in one flow — the
    /// way a home shelf runs one row of equal tiles rather than sorting them into
    /// pens by shape.
    var cellWidth: CGFloat { CGFloat(tileWidth) * (isLandscape ? 1.6 : 1) }

    /// How wide a video file is drawn: exactly a Continue Watching card.
    ///
    /// Asked for directly, and it is the right size for what these tiles are. A
    /// loose file in one of these libraries has no scraped poster — its picture is
    /// a frame grab off the video, which is 16:9 — so it is the same kind of tile
    /// as the one on the home row, and two sizes for one kind of thing is the
    /// mismatch that was visible between the two screens.
    ///
    /// Fixed rather than driven by the tile slider. The slider still sizes the
    /// *folder* tiles above them, which is the thing on this wall whose size is a
    /// matter of taste; a video card that matches the home screen is not.
    var fileWidth: CGFloat { Theme.Art.continueCardWidth }

    /// The two shapes, kept apart. Sorted folders-first already, so splitting the
    /// list preserves the order rather than inventing one.
    var visibleFolders: [LibraryEntry] { visibleEntries.filter { $0.item.isFolder } }

    /// Files, in the order of the names actually printed under them.
    ///
    /// Re-sorted rather than left in the repository's order, which is by the
    /// item's metadata name — and a wall labelled with filenames but ordered by
    /// something else is one you cannot scan, and one the A–Z rail cannot point
    /// into honestly.
    var visibleFiles: [LibraryEntry] {
        visibleEntries
            .filter { !$0.item.isFolder }
            .sorted {
                displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending
            }
    }

    private var currentId: String { path.last?.id ?? libraryId }

    // Not private, here and below: FolderBrowserView+Wall.swift draws with these
    // and Swift scopes `private` to the file.
    var visibleEntries: [LibraryEntry] {
        let needle = shelfFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        // Both the drawn title and the item's name. A file is labelled with its
        // filename here, so that has to match; the metadata name is kept as a
        // second key because it is sometimes the tidier of the two and someone
        // typing it should not come up empty.
        return entries.filter {
            displayName($0).lowercased().contains(needle)
                || $0.item.name.lowercased().contains(needle)
        }
    }

    /// Folders and files share one rail. They are sorted folders-first, so the
    /// letters point at whichever comes first under each — which is what someone
    /// jumping to "S" in a folder of both actually wants.
    var railDestinations: [String: String] {
        AlphabetIndex.firstIds(
            in: visibleFolders + visibleFiles,
            id: { $0.id },
            sortKey: { displayName($0) },
            name: { displayName($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            content
        }
        .background(Theme.Palette.canvas)
        // The shared sheets. Most stay shut here — see `allowsMetadata` in
        // `actions(for:)` — but Add to Playlist is offered and needs a host, or
        // it is a menu item that opens nothing.
        .entryActions(entryState, in: entryContext)
        .safeAreaInset(edge: .bottom) {
            if selection.isActive {
                BatchActionBar(
                    selection: selection,
                    totalVisible: visibleEntries.count,
                    onSelectAll: { selection.selectAll(visibleEntries.map(\.id)) },
                    onFavourite: nil,
                    onMarkWatched: { await batchWatched($0) },
                    onAddToCollection: nil,
                    onAddToPlaylist: nil
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(Theme.Motion.transition, value: selection.isActive)
        .task(id: currentId) { await load() }
        // A whole reload, unlike the paged grids: this is one folder's listing,
        // it does not page, and the tick on a file is the thing most likely to
        // have changed while the player was over this view.
        // Every change, including a sync of this library: a folder wall is one
        // listing rather than a paged grid, so reloading it costs nothing to
        // reload and is the only way new files appear.
        .onLibraryChange { _ in
            await load()
            columnCache.removeAll()
        }
    }

    // MARK: - Path

    private var breadcrumb: some View {
        HStack(spacing: Theme.Space.xs) {
            // Always a way back to the root, however deep you went.
            Button(title) { path = [] }
                .buttonStyle(.plain)
                .foregroundStyle(path.isEmpty ? Theme.Palette.textPrimary : Theme.Palette.accent)

            ForEach(Array(path.enumerated()), id: \.offset) { index, level in
                Image(systemName: "chevron.right")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                Button(level.name) {
                    // Truncating rather than popping one level, so clicking a mid-path
                    // crumb goes there directly.
                    path = Array(path.prefix(index + 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    index == path.count - 1 ? Theme.Palette.textPrimary : Theme.Palette.accent
                )
            }
            Spacer()
            ShelfSearchField(
                text: $shelfFilter,
                placeholder: "Filter folder",
                matchCount: visibleEntries.count
            )
            Button { selection.isActive ? selection.end() : selection.begin() } label: {
                Image(systemName: selection.isActive
                      ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(selection.isActive
                             ? Theme.Palette.accent : Theme.Palette.textSecondary)
            .labelledHelp("Select several files and act on all of them")

            viewModeControl
            // The tile controls only mean something to the wall: a list has no
            // tiles to shape or resize, and a column pane is a fixed width by
            // definition. Showing them disabled would be three dead controls.
            if viewMode == .icon {
                shapeControl
                tileSizeControl
            }
            Text("\(visibleEntries.count) items")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .font(Theme.Font.body)
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
    }

    private func batchWatched(_ played: Bool) async {
        await selection.run { await repository.setPlayed(itemId: $0, played: played) }
        await load()
    }

    // Not private: FolderBrowserView+Cells.swift re-reads the folder after a
    // right-click command changes something in it.
    func load() async {
        isLoading = true
        shelfFilter = ""
        // Navigation ends a selection. Carrying one into another folder means
        // acting on things you can no longer see.
        selection.end()
        defer { isLoading = false }
        // At the top of a library the id to ask for is *not* the library's own —
        // that is a view id and nothing is filed under it. See libraryRootChildren.
        entries = (try? await (path.isEmpty
            ? repository.libraryRootChildren(libraryId: libraryId)
            : repository.folderChildren(parentId: currentId))) ?? []
        // Only meaningful at the root: an empty subfolder really is empty.
        neverSynced = entries.isEmpty && path.isEmpty
    }
}
