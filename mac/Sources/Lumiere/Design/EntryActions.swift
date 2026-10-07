import SwiftUI
import LumiereKit

/// The right-click menu, once, for any surface that shows library tiles.
///
/// Eight surfaces had each built this menu themselves, which is why three others —
/// genre browse, the "latest" See All grid, a person's filmography — had no menu at
/// all: nothing carried it there, so nothing noticed it was missing. A tile you
/// cannot act on is a picture of your library rather than your library, and whether
/// you can act on it should not depend on which page you happened to arrive from.
///
/// Split in two for the 300-line rule: the state and the menu here, the sheets those
/// commands open in EntryActions+Sheets.swift.
@MainActor
@Observable
final class EntryActionState {
    var artworkPickerItem: String?
    var identifyEntry: LibraryEntry?
    var editEntry: LibraryEntry?
    var collectionEntry: LibraryEntry?
    var playlistEntry: LibraryEntry?
}

/// What a surface has to lend the menu: somewhere to write, and a way to show the
/// result. Passed as one value because the menu and its sheets both need all of it,
/// and a surface that hands the menu one context and the sheets another is a bug
/// waiting for someone to edit only half of it.
struct EntryActionContext {
    let app: AppModel?
    let repository: LibraryRepository
    /// Re-reads one row after a write.
    ///
    /// The row, not the page. A reload refetches from offset zero and takes the
    /// scroll position with it, which on a long grid is the difference between
    /// seeing your change and losing your place.
    let refreshRow: (String) async -> Void
}

/// The commands one surface has that the others do not.
///
/// The menu was built independently at seven sites, and it drifted at every one
/// of them: the home shelves had no offline guards and no playlists, the music
/// browser fired its destructive command without asking, and the same sheet was
/// called "Choose Artwork…" in two places and "Choose or Remove Artwork…" in
/// two others. Which commands you got, and whether the dangerous one asked
/// first, depended on which page the tile happened to be on.
///
/// So the shared builder owns everything common, and a surface supplies only
/// what is genuinely its own. There is no route left for a label or a guard to
/// differ by accident — only by someone deciding it should.
struct EntryActionExtras {
    /// Home only: there is nothing to hide an item *from* in a library grid.
    var hideFromShelves: ((String) async -> Void)?
    /// Grids and walls, where picking several is a real gesture.
    var beginSelection: ((String) -> Void)?
    /// Folder walls, where files arrive with no artwork for a provider to match.
    var generateThumbnail: ((String) -> Void)?
    /// Only ever on a BoxSet. This app never deletes media.
    var deleteCollection: ((LibraryEntry) -> Void)?
    /// Whether the surface can scrape at all.
    ///
    /// The folder-browsed libraries — 3D, My Videos — deliberately have no
    /// provider behind them, so Refresh, Identify and Collections are not
    /// commands that could work there.
    var allowsMetadata = true
}

extension EntryActionState {

    func actions(
        for entry: LibraryEntry,
        in context: EntryActionContext,
        extras: EntryActionExtras = EntryActionExtras()
    ) -> MetadataActions? {
        guard let app = context.app else { return nil }
        // Everything here except Select writes to the server, so with the server away
        // each item is a click that opens a sheet, searches, and shows a transport
        // error. The commands stay and each says what it needs, because a menu that
        // silently loses six items reads as a broken menu. See `AppModel.refuseOffline`.
        let offline = app.isOffline
        let refreshRow = context.refreshRow
        let id = entry.item.id
        return MetadataActions(
            itemId: id,
            title: entry.item.name,
            refresh: extras.allowsMetadata ? { replaceEverything in
                guard !offline else { return app.refuseOffline("Refreshing metadata") }
                await app.refreshMetadata(
                    itemId: entry.item.id, replaceEverything: replaceEverything
                )
                await refreshRow(entry.item.id)
            } : nil,
            chooseArtwork: {
                guard !offline else { return app.refuseOffline("Choosing artwork") }
                self.artworkPickerItem = entry.item.id
            },
            identify: extras.allowsMetadata ? {
                guard !offline else { return app.refuseOffline("Identify") }
                self.identifyEntry = entry
            } : nil,
            editMetadata: {
                guard !offline else { return app.refuseOffline("Editing metadata") }
                self.editEntry = entry
            },
            hideFromShelves: extras.hideFromShelves.map { hide in
                { await hide(id) }
            },
            addToCollection: !extras.allowsMetadata
                || entry.item.itemType == .boxSet ? nil : {
                guard !offline else { return app.refuseOffline("Collections") }
                self.collectionEntry = entry
            },
            isFavourite: entry.userData?.isFavorite ?? false,
            toggleFavourite: {
                // Not guarded: `toggleFavourite` refuses for itself, so this menu gets
                // the same answer as the detail page and the batch bar.
                await app.toggleFavourite(
                    itemId: entry.item.id,
                    isFavourite: entry.userData?.isFavorite ?? false
                )
                await refreshRow(entry.item.id)
            },
            isWatched: entry.isPlayed,
            toggleWatched: entry.supportsWatchState ? {
                // Watch state is an account fact, like the star above it, so an
                // offline write would either be lost or need replaying later — a much
                // larger promise than this makes.
                guard !offline else { return app.refuseOffline("Changing watch state") }
                await app.changeWatchState(of: entry, watched: !entry.isPlayed) {
                    await app.repository?.setPlayed(
                        itemId: entry.item.id, played: !entry.isPlayed
                    )
                }
                await refreshRow(entry.item.id)
            } : nil,
            // Anything with watch state to clear, which includes a
            // part-watched item the toggle above calls unwatched.
            markUnwatched: entry.supportsWatchState
                && (entry.isPlayed || entry.userData?.isInProgress == true) ? {
                // `clearWatchState`, not `setPlayed(played: false)`. The latter
                // cannot clear a resume position, which is the whole point of
                // this command — see `LibraryRepository.clearWatchState`.
                await app.changeWatchState(of: entry, watched: false) {
                    await app.repository?.clearWatchState(itemId: entry.item.id)
                }
                await refreshRow(entry.item.id)
            } : nil,
            addToPlaylist: {
                guard !offline else { return app.refuseOffline("Playlists") }
                self.playlistEntry = entry
            },
            beginSelection: extras.beginSelection.map { begin in { begin(id) } },
            generateThumbnail: extras.generateThumbnail.map { make in { make(id) } },
            deleteCollection: entry.item.itemType == .boxSet
                ? extras.deleteCollection.map { delete in { delete(entry) } }
                : nil,
            removeFromLibrary: !Preference.allowsRemoval.value ? nil : {
                guard !offline else { return app.refuseOffline("Removing") }
                if await context.repository.removeFromLibrary(itemId: id) {
                    app.report("\(entry.item.name) removed. Restore it from Settings › Library.")
                    await app.contentDidChange("after removal")
                } else {
                    app.report("The server would not remove \(entry.item.name).")
                }
            },
            deleteToTrash: !Preference.allowsRemoval.value ? nil : {
                guard !offline else { return app.refuseOffline("Deleting") }
                do {
                    try await context.repository.deleteToTrash(itemId: id)
                    app.reportTrashed("\(entry.item.name)")
                    await app.contentDidChange("after deletion")
                } catch {
                    // The server's own sentence where it has one — "this
                    // volume has no Trash" is the one worth reading.
                    app.report(ConnectionState.message(for: error))
                }
            }
        )
    }
}
