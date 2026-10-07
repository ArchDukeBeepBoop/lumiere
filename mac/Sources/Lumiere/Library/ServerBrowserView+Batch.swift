import SwiftUI
import LumiereKit

/// The action bar and playlist sheet a music selection uses.
///
/// An extension on the view rather than a standalone modifier, so the selection it
/// clears is the browser's own state. Split out for the project's 300-line limit.
extension ServerBrowserView {
    func withBatch(_ content: some View) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if selection.isActive {
                    BatchActionBar(
                        selection: selection,
                        totalVisible: entries.count,
                        onSelectAll: { selection.selectAll(entries.map(\.id)) },
                        onFavourite: { await batchFavourite() },
                        onMarkWatched: nil,
                        onAddToCollection: nil,
                        onAddToPlaylist: { batchPlaylistIds = Array(selection.ids) }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(Theme.Motion.transition, value: selection.isActive)
            .sheet(isPresented: Binding(
                get: { !batchPlaylistIds.isEmpty },
                set: { if !$0 { batchPlaylistIds = [] } }
            )) {
                AddToPlaylistSheet(
                    itemIds: batchPlaylistIds,
                    itemName: "\(batchPlaylistIds.count) tracks",
                    repository: repository,
                    onDone: { batchPlaylistIds = [] }
                )
            }    }
}
