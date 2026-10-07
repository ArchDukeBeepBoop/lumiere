import SwiftUI
import LumiereKit

/// What right-clicking a poster offers.
///
/// Everything here runs on the *server*, through the metadata providers Jellyfin is
/// already configured with. That is the point: no API key lives in this app, and the
/// project's rule that Jellyfin is the only metadata source stays intact. A refresh
/// also benefits every other client on the server rather than just this one.
struct MetadataActions {
    let itemId: String
    let title: String
    /// Re-scrapes on the server. Optional like its neighbours, because a surface
    /// that has only the repository and no `AppModel` — the folder browser, which
    /// the shell builds without one — can still offer the commands it *can* honour
    /// rather than offering none. A refresh that cannot reach the server is the
    /// same broken menu item as a `chooseArtwork: {}` was.
    var refresh: ((Bool) async -> Void)?
    /// Opens the artwork picker — which is also where artwork is *removed*, so a
    /// context without it has no way to delete a wrong poster at all.
    ///
    /// Optional like its neighbours, and that is the fix rather than a style
    /// preference: it used to be non-optional, so three call sites satisfied the
    /// compiler with `chooseArtwork: {}` and the menu item rendered, was clicked,
    /// and did nothing — on Continue Watching and Favourites, which is exactly
    /// where a wrong thumbnail is most visible. An optional cannot be silenced
    /// that way; it either does something or it is not in the menu.
    var chooseArtwork: (() -> Void)?
    /// Opens the Identify sheet. Nil where there is nothing to identify.
    var identify: (() -> Void)?
    /// Opens the metadata editor. Nil where there is no client to write with.
    var editMetadata: (() -> Void)?
    /// Nil outside the home shelves — there is nothing to hide an item *from* in a
    /// library grid, and offering it there would be meaningless.
    var hideFromShelves: (() async -> Void)?
    /// Opens the Add to Collection sheet. Nil where there is no repository to ask
    /// for the collection list — a preview or demo context.
    var addToCollection: (() -> Void)?
    /// Whether the item is starred, and how to change it. Server-backed, so a star
    /// set from any grid shows in every other Jellyfin client.
    var isFavourite: Bool?
    var toggleFavourite: (() async -> Void)?
    /// Whether the item is watched, and how to flip it. Server-backed through
    /// `LibraryRepository.setPlayed`, the same call the detail page and the batch
    /// bar already use, so a tick set from a right-click is the same write as one
    /// set from the page — and shows on every other Jellyfin client.
    ///
    /// Here rather than per-surface because "mark this unwatched" is the command
    /// people go looking for on whatever tile is in front of them: a home shelf, a
    /// search result, a favourite, a file in a folder. Nil only where the item has
    /// no watch state to speak of — see `LibraryEntry.supportsWatchState`.
    var isWatched: Bool?
    var toggleWatched: (() async -> Void)?
    /// Clears watch state outright, rather than flipping it.
    ///
    /// The toggle above is not enough on its own, and the gap only shows on the
    /// items people most want to act on. A part-watched episode has `played == false`
    /// — it is in Continue Watching precisely because it is unfinished — so the
    /// toggle offered "Mark as Watched" and there was no way at all to say "I am not
    /// watching this after all". Marking it watched is a lie that removes it; hiding
    /// it keeps the history and only conceals the tile. Neither clears the resume
    /// position, which is the thing actually being complained about.
    ///
    /// Present whenever there is any watch state to clear — played, or part-played.
    /// Nil on something never started, where it would do nothing.
    var markUnwatched: (() async -> Void)?
    /// Opens the Add to Playlist sheet. Playlists are not only for music — a
    /// Jellyfin playlist holds films and episodes just as happily.
    var addToPlaylist: (() -> Void)?
    /// Starts a batch selection with this item already chosen. The gesture people
    /// reach for first — you notice the second thing you want *while looking at
    /// the first*, not before opening a toolbar.
    var beginSelection: (() -> Void)?
    /// Deletes a collection. Only ever set on a BoxSet — there is no equivalent for
    /// a film, and this app never deletes media.
    /// Replaces the tile's artwork with a frame taken from the file itself.
    ///
    /// In the shared menu rather than only on a detail page's episodes, because the
    /// folder-browsed libraries are precisely where files arrive with no artwork at
    /// all — an un-scraped clip has nothing for a provider to have matched.
    var generateThumbnail: (() -> Void)?
    var deleteCollection: (() -> Void)?
    /// Out of the library, file untouched, restorable from Settings. Nil where
    /// the owner has switched removal off — see `Preference.allowsRemoval`.
    var removeFromLibrary: (() async -> Void)?
    /// To the Trash. Nil under the same switch. Confirmed, always.
    var deleteToTrash: (() async -> Void)?
}

struct MetadataContextMenu: ViewModifier {
    let actions: MetadataActions?

    @State private var confirmingReplace = false
    @State private var confirmingRemove = false
    @State private var confirmingDelete = false

    /// Every modifier here is attached to *every tile on screen* — a few hundred
    /// of them on the home screen — so each one has to earn its place per card,
    /// not per use.
    ///
    /// The first version attached three unconditionally: a long-press recognizer,
    /// a popover mirroring the menu for that long press, and a confirmation
    /// dialog for one command. Two of the three were dead on most cards, and the
    /// cost showed up as menus that were slow to appear and shelves that
    /// stuttered under the cursor.
    ///
    /// So: the long press exists only where it starts a selection, and the
    /// dialog only where there is a refresh to confirm. The popover is gone
    /// altogether. It was a fallback route to the same items for a gesture that
    /// no longer opens anything, on a platform where every mouse right-clicks —
    /// a duplicate menu built on cards that had no second way to reach it.
    func body(content: Content) -> some View {
        if let actions {
            content
                .contextMenu { menuItems(actions) }
                .modifier(SelectionPress(begin: actions.beginSelection))
                .modifier(
                    ReplaceConfirmation(
                        actions: actions, isPresented: $confirmingReplace
                    )
                )
                .modifier(
                    RemovalConfirmations(
                        actions: actions,
                        confirmingRemove: $confirmingRemove,
                        confirmingDelete: $confirmingDelete
                    )
                )
        } else {
            content
        }
    }

    @ViewBuilder
    private func menuItems(_ actions: MetadataActions) -> some View {
        if let beginSelection = actions.beginSelection {
            Button("Select…") {
                beginSelection()
            }
            Divider()
        }
        // First, and above the refreshes on purpose. Editing is the deliberate act;
        // the two below it are the ones that can undo an edit that was not locked,
        // so the menu reads in the order someone should think about them.
        if let edit = actions.editMetadata {
            Button("Edit Metadata…") {
                edit()
            }
            Divider()
        }
        // Favourite and playlist sit above the scraping commands: they are what
        // someone reaches this menu for most often, and neither has anything to do
        // with metadata.
        if let toggle = actions.toggleFavourite {
            Button(actions.isFavourite == true ? "Remove from Favourites" : "Add to Favourites") {
                Task { await toggle() }
            }
        }
        // Directly under the star: the same kind of thing, a one-click fact
        // about your relationship to the item. The label states the outcome.
        // Both, where both apply. On a part-watched item the toggle reads "Mark as
        // Watched", so the command that clears progress needs its own line rather
        // than sharing one — see `markUnwatched`.
        if actions.isWatched != true, let markUnwatched = actions.markUnwatched {
            Button("Mark as Unwatched") {
                Task { await markUnwatched() }
            }
        }
        if let toggleWatched = actions.toggleWatched {
            Button(actions.isWatched == true ? "Mark as Unwatched" : "Mark as Watched") {
                Task { await toggleWatched() }
            }
        }
        if let addToPlaylist = actions.addToPlaylist {
            Button("Add to Playlist…") {
                addToPlaylist()
            }
        }
        // Only when there is something below it to divide from. The folder browser's
        // menu ends here — it has no scraping commands at all — and a rule under the
        // last item reads as a command that failed to draw.
        if actions.toggleFavourite != nil || actions.toggleWatched != nil
            || actions.markUnwatched != nil
            || actions.addToPlaylist != nil,
           actions.refresh != nil || actions.chooseArtwork != nil
            || actions.identify != nil || actions.addToCollection != nil {
            Divider()
        }
        if let refresh = actions.refresh {
            Button("Refresh Metadata") {
                Task { await refresh(false) }
            }
            // Confirmed, unlike the plain refresh above it. It is destructive in the
            // sense that matters — it discards corrections made by hand on the server
            // — and Settings' equivalent ("Replace All Posters…") has always asked
            // first while this fired on click.
            Button("Replace Metadata and Artwork…") {
                confirmingReplace = true
            }
            Divider()
        }
        // Covers poster, thumb and backdrop now, not just the poster — the
        // name says so, since the sheet it opens picks the type inside.
        if let chooseArtwork = actions.chooseArtwork {
            Button("Choose or Remove Artwork…") {
                chooseArtwork()
            }
        }
        if let generateThumbnail = actions.generateThumbnail {
            Button("Use Frame from File as Thumbnail") {
                generateThumbnail()
            }
        }
        if let identify = actions.identify {
            Button("Identify…") {
                identify()
            }
        }
        if let addToCollection = actions.addToCollection {
            Button("Add to Collection…") {
                addToCollection()
            }
        }
        if let hide = actions.hideFromShelves {
            Divider()
            Button("Hide from Continue Watching") {
                Task { await hide() }
            }
        }
        // Last, under a divider: the commands that remove rather than change.
        if let deleteCollection = actions.deleteCollection {
            Divider()
            Button("Delete Collection…", role: .destructive) {
                deleteCollection()
            }
        }
        // Two words for two acts: Remove keeps the file, Delete trashes it.
        // Both ask first — see RemovalConfirmations.
        if actions.removeFromLibrary != nil || actions.deleteToTrash != nil {
            Divider()
        }
        if actions.removeFromLibrary != nil {
            Button("Remove from Library…") { confirmingRemove = true }
        }
        if actions.deleteToTrash != nil {
            Button("Delete File…", role: .destructive) { confirmingDelete = true }
        }
    }
}

/// Asks before "Replace Metadata and Artwork…" discards hand-made corrections.
///
/// Attached only where that command exists, for the same reason as above.
private struct ReplaceConfirmation: ViewModifier {
    let actions: MetadataActions
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if actions.refresh != nil {
            content.confirmationDialog(
                "Replace \(actions.title)'s metadata and artwork?",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    Task { await actions.refresh?(true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Re-scrapes from your server's providers and overwrites what "
                   + "is there now, including titles, synopses and posters you "
                   + "corrected by hand. Locked fields are kept.")
            }
        } else {
            content
        }
    }
}


