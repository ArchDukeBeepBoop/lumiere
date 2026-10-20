import SwiftUI
import LumiereKit

/// Selecting many search results and acting on all of them — the library
/// grid's selection, on search. Search drew its own tiles and never offered
/// "Select…" or ⌘-click, so a batch had to be gathered one title at a time.
extension SearchView {
    @ViewBuilder
    func searchTile(_ entry: LibraryEntry, wide: Bool) -> some View {
        if selection.isActive {
            Button { selection.toggle(entry.id) } label: {
                card(entry, wide: wide, metadata: nil)
                    .overlay { SelectionOverlay(isSelected: selection.contains(entry.id)) }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: DetailRoute.forEntry(entry)) {
                card(entry, wide: wide, metadata: actions(for: entry))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func card(_ entry: LibraryEntry, wide: Bool, metadata: MetadataActions?) -> some View {
        if wide {
            WideCard(entry: entry, serverURL: serverURL, pipeline: pipeline,
                     width: Theme.Art.continueCardWidth * 0.7, metadata: metadata)
        } else {
            PosterCard(entry: entry, serverURL: serverURL, pipeline: pipeline,
                       width: Theme.Art.shelfPosterWidth, metadata: metadata)
        }
    }

    func withSearchSelection(_ content: some View, all: [String]) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if selection.isActive {
                    BatchActionBar(
                        selection: selection,
                        totalVisible: all.count,
                        onSelectAll: { selection.selectAll(all) },
                        onFavourite: {
                            guard let app else { return }
                            await selection.run { await app.toggleFavourite(itemId: $0, isFavourite: false) }
                        },
                        onMarkWatched: { played in
                            await selection.run { await repository.setPlayed(itemId: $0, played: played) }
                        },
                        onAddToCollection: { batchIds = (Array(selection.ids), false) },
                        onAddToPlaylist: { batchIds = (Array(selection.ids), true) }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(Theme.Motion.transition, value: selection.isActive)
            .sheet(isPresented: Binding(get: { !batchIds.ids.isEmpty }, set: { if !$0 { batchIds = ([], false) } })) {
                if batchIds.playlist {
                    AddToPlaylistSheet(itemIds: batchIds.ids, itemName: "\(batchIds.ids.count) titles",
                                       repository: repository, onDone: { batchIds = ([], false) })
                } else {
                    AddToCollectionSheet(itemId: batchIds.ids.first ?? "", itemIds: batchIds.ids,
                                         itemName: "\(batchIds.ids.count) titles", repository: repository,
                                         onDone: { batchIds = ([], false); search() })
                }
            }
    }
}
