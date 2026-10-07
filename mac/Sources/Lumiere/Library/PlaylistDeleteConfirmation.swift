import SwiftUI
import LumiereKit

/// The confirmation a playlist deletion goes through.
///
/// An extension on the view rather than a standalone `ViewModifier`, so it writes
/// back to the browser's own `@State` — a modifier holds a copy of the view, which
/// can present a dialog but is a poor place to put the state it clears.
///
/// Its own file for the project's 300-line limit, and the separation is earned by
/// the wording: "Delete" beside a list of songs reads as though it deletes the
/// songs, and a playlist is an order to play things in rather than a place they
/// are kept.
extension ServerBrowserView {
    func withPlaylistDelete(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Delete \(deleteTarget?.name ?? "this playlist")?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    if let target = deleteTarget {
                        Task { await deletePlaylist(id: target.id) }
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                // Same reassurance a collection gets, and needed for the same reason: a
                // playlist is an ordering of tracks, not a place they are kept.
                Text("Removes the playlist from your server. Every track in it stays in "
                   + "your library exactly where it is — a playlist is an order to play "
                   + "things in, not a place they are stored. Nothing is deleted from disk.")
            }
    }
}
