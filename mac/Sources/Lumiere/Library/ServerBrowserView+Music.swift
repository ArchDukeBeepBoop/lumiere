import SwiftUI
import LumiereKit

/// Right-click behaviour for the music browser, the alphabet rail, and playlist
/// editing.
///
/// Split from ServerBrowserView.swift, which is already at the project's 300-line
/// limit. These three belong together: each is a way of acting on a row rather than
/// merely reading one, and they share the same optimistic-then-reconcile approach —
/// the UI moves on the click, the server is told, and the next load is the truth.
extension ServerBrowserView {

    /// How to read a music library. Folders are how it sits on disk; the rest are
    /// the ways someone actually thinks about music.
    enum Scope: String, CaseIterable, Identifiable {
        case albums, artists, genres, tracks, favourites, folders

        var id: String { rawValue }

        var title: String {
            switch self {
            case .albums: return "Albums"
            case .artists: return "Artists"
            case .genres: return "Genres"
            case .tracks: return "Tracks"
            case .favourites: return "Favourites"
            case .folders: return "Folders"
            }
        }

        var types: [JellyfinItem.ItemType] {
            switch self {
            case .albums: return [.musicAlbum]
            case .artists: return [.musicArtist]
            case .genres: return [.musicGenre]
            case .tracks: return [.audio]
            // Favourites and Folders are not type queries — one asks the server for
            // starred items, the other walks the tree — so they carry no types and
            // are routed separately in `load`.
            case .favourites, .folders: return []
            }
        }

        /// Everything sorts by name. Tracks used to group by album first, which read
        /// well until the alphabet rail arrived: a rail can only jump if the list is
        /// monotonic, and album order sends "Africa" past "Zombie" and back again.
        /// Album order is what the Albums scope is for.
        var sortBy: [String] { ["SortName"] }
    }

    // MARK: - Context menu

    /// What right-clicking a track, album or artist offers.
    ///
    /// The one menu in the app that is not built from `EntryActionState`, and
    /// the only one that should not be.
    ///
    /// Every other surface — the grids, the walls, the search results, all three
    /// home layouts — now composes the same builder, because they all show the
    /// same object and had drifted apart only by accident. Music has not drifted;
    /// it is a different vocabulary. Play Next, Edit Track, Remove from Playlist
    /// and Delete Playlist have no meaning on a film, and watch state, Identify,
    /// Collections and Hide from Continue Watching have none on a song.
    ///
    /// What it *does* share is the part that was an accident: the same words for
    /// the same commands, the same confirmation before the destructive one, and
    /// the same offline guards. Those are below rather than inherited, and that
    /// is the cost of keeping this menu its own — worth paying, but worth
    /// stating.
    @ViewBuilder
    func musicMenu(for entry: LibraryEntry) -> some View {
        let type = entry.item.itemType

        if type == .audio, let music = app?.music {
            Button("Play Next") { music.playNext(entry) }
            Divider()
        }

        Button(isFavourite(entry) ? "Remove from Favourites" : "Add to Favourites") {
            Task { await toggleFavourite(entry) }
        }
        Button("Add to Playlist…") { playlistTarget = entry }

        if type == .audio, app?.client != nil {
            Button("Edit Track…") { trackEditTarget = entry }
        }

        if isPlaylist, let entryId = playlistEntryIds[entry.id] {
            Button("Remove from Playlist", role: .destructive) {
                Task { await removeFromPlaylist(entryId: entryId) }
            }
        }

        // At the playlists root every row *is* a playlist, which is the only place
        // this is unambiguous: Jellyfin's Playlist type is one this app decodes as
        // unknown, so position is a better signal than the item's own type.
        if isPlaylist, path.isEmpty {
            Divider()
            Button("Delete Playlist…", role: .destructive) {
                deleteTarget = PlaylistTarget(id: entry.id, name: entry.item.name)
            }
        }

        // Containers only. A single track's Primary image *is* its album's cover on
        // Jellyfin, so offering to replace it per-song would be four ways to set the
        // same picture and one way to get them out of step.
        if type == .musicAlbum || type == .musicArtist {
            Divider()
            // The same words as the shared menu's: the sheet this opens is
            // also where artwork is removed.
            Button("Choose or Remove Artwork…") {
                guard app?.isOffline != true else {
                    return app?.refuseOffline("Choosing artwork") ?? ()
                }
                artworkTarget = entry
            }
            Button("Refresh Metadata") {
                guard app?.isOffline != true else {
                    return app?.refuseOffline("Refreshing metadata") ?? ()
                }
                Task { await refreshMetadata(entry, replaceEverything: false) }
            }
            Button("Replace Metadata and Artwork…") {
                guard app?.isOffline != true else {
                    return app?.refuseOffline("Replacing metadata") ?? ()
                }
                replaceTarget = entry
            }
        }

        // The same two doors out as everywhere else, in the same words. See
        // `RemovalTarget`.
        if Preference.allowsRemoval.value, app?.client != nil, !isPlaylist {
            Divider()
            Button("Remove from Library…") {
                removalTarget = RemovalTarget(entry: entry, permanent: false)
            }
            Button("Delete File…", role: .destructive) {
                removalTarget = RemovalTarget(entry: entry, permanent: true)
            }
        }
    }

    /// A row that selects instead of playing, while a selection is live.
    ///
    /// The whole row is the target, as in the grids: a checkbox column would move
    /// every title sideways the moment selection turned on, and a list that
    /// reflows under the pointer is worse than one extra click.
    @ViewBuilder
    func selectable(_ entry: LibraryEntry) -> some View {
        if selection.isActive {
            Button { selection.toggle(entry.id) } label: {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: selection.contains(entry.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selection.contains(entry.id)
                                         ? Theme.Palette.accent : Theme.Palette.textMuted)
                        .padding(.leading, Theme.Space.lg)
                    row(entry)
                        .allowsHitTesting(false)
                }
                .background(selection.contains(entry.id)
                            ? Theme.Palette.surfaceRaised : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            menued(row(entry), for: entry)
        }
    }

    /// Stars everything selected, rather than toggling each: a toggle over a mixed
    /// selection turns half of it off, which nobody means by "favourite these".
    func batchFavourite() async {
        await selection.run { await repository.setFavorite(itemId: $0, favorite: true) }
        await load()
    }

    /// The optimistic value where one exists, the cached one otherwise.
    func isFavourite(_ entry: LibraryEntry) -> Bool {
        favouriteOverrides[entry.id] ?? (entry.userData?.isFavorite ?? false)
    }

    func toggleFavourite(_ entry: LibraryEntry) async {
        let wanted = !isFavourite(entry)
        favouriteOverrides[entry.id] = wanted
        let ok = await repository.setFavorite(itemId: entry.id, favorite: wanted)
        if !ok {
            // The repository already rolled its own local write back; drop the
            // override so the row shows what the cache now says.
            favouriteOverrides[entry.id] = nil
        }
    }

    func refreshMetadata(_ entry: LibraryEntry, replaceEverything: Bool) async {
        await app?.refreshMetadata(itemId: entry.id, replaceEverything: replaceEverything)
        await load()
    }

    /// Deletes the playlist and reloads whatever list is on screen.
    ///
    /// Steps back out first when the deleted playlist is the one being browsed —
    /// staying inside a playlist that no longer exists leaves a breadcrumb pointing
    /// at nothing and an empty list that reads as a failure to load.
    func deletePlaylist(id: String) async {
        do {
            try await repository.deletePlaylist(id: id)
            if path.last?.id == id { path.removeLast() }
            await load()
        } catch {
            Diagnostics.log("[playlist] delete failed: \(id): \(error)")
            // Said on screen as well as in the log. The reload below puts the row
            // straight back, so silence here reads as "the button does nothing"
            // rather than "the server refused" — and `AppModel.report` is how every
            // other refusal in the app reaches the user.
            app?.report(ConnectionState.message(for: error))
        }
    }

    /// What a pending playlist deletion needs to know.
    struct PlaylistTarget: Identifiable, Hashable {
        let id: String
        let name: String
    }

    func removeFromPlaylist(entryId: String) async {
        await removeFromPlaylist(entryIds: [entryId])
    }

    /// Removes several rows at once — a whole series, or a batch.
    ///
    /// One request rather than one per row: Jellyfin takes a comma-separated list of
    /// entry ids, and twelve round trips to remove a season is twelve chances for
    /// the list to be half-removed when one of them fails.
    func removeFromPlaylist(entryIds: [String]) async {
        guard !entryIds.isEmpty else { return }
        do {
            try await repository.removeFromPlaylist(playlistId: currentId, entryIds: entryIds)
        } catch {
            // Same reasoning as `deletePlaylist`: the reload restores the rows, so
            // without this the removal looks like it simply did not happen.
            app?.report(ConnectionState.message(for: error))
        }
        await load()
    }

    // MARK: - Alphabet rail

    /// Where each letter jumps to, for the shared rail.
    ///
    /// The rail itself used to live here at nine points, which was small enough to
    /// be fiddly. It is one component now, used by every shelf.
    var railDestinations: [String: String] {
        AlphabetIndex.firstIds(
            in: entries,
            id: { $0.id },
            sortKey: { $0.item.sortName },
            name: { $0.item.name }
        )
    }

}
