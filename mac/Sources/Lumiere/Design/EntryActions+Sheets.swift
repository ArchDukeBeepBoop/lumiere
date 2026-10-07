import SwiftUI
import LumiereKit

/// The sheets the shared right-click menu opens.
///
/// One modifier rather than five per surface. Split from EntryActions.swift for the
/// 300-line rule; see the type comment there for why the menu is shared at all.
extension View {

    /// The context is optional because a home layout has none until its library
    /// has loaded, and a modifier that appears only once loading finishes
    /// changes the view's identity mid-flight. With no context there is nothing
    /// any of these sheets could write to, so they are simply not attached —
    /// and no command that opens one exists either, for the same reason.
    func entryActions(
        _ state: EntryActionState, in context: EntryActionContext?
    ) -> some View {
        modifier(EntryActionSheets(state: state, context: context))
    }
}

private struct EntryActionSheets: ViewModifier {
    @Bindable var state: EntryActionState
    let context: EntryActionContext?

    func body(content: Content) -> some View {
        if let context { sheets(content, context) } else { content }
    }

    @ViewBuilder
    private func sheets(_ content: Content, _ context: EntryActionContext) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { state.artworkPickerItem != nil },
                set: { if !$0 { state.artworkPickerItem = nil } }
            )) { artworkPicker(context) }
            .sheet(item: $state.identifyEntry) { entry in
                if let app = context.app, let client = app.client {
                    IdentifySheet(
                        itemId: entry.item.id,
                        // Seeded from the folder on disk, not from the scraped name.
                        // The scraped name is the one string known to be wrong when
                        // Identify is the sheet you just opened.
                        initialQuery: PathTitleGuess.query(
                            path: entry.item.path,
                            isFolder: entry.item.isFolder,
                            fallback: entry.item.name
                        ),
                        isSeries: entry.item.itemType == .series,
                        client: client,
                        onDone: { changed in
                            state.identifyEntry = nil
                            guard changed else { return }
                            // The server scrapes asynchronously, so a pause before
                            // re-reading is the difference between seeing the new
                            // title and thinking nothing happened.
                            Task {
                                await app.refreshMetadata(
                                    itemId: entry.item.id, replaceEverything: false
                                )
                                await context.refreshRow(entry.item.id)
                            }
                        }
                    )
                }
            }
            .sheet(item: $state.collectionEntry) { entry in
                AddToCollectionSheet(
                    itemId: entry.item.id, itemName: entry.item.name,
                    repository: context.repository,
                    onDone: { state.collectionEntry = nil }
                )
            }
            .sheet(item: $state.playlistEntry) { entry in
                AddToPlaylistSheet(
                    itemIds: [entry.id], itemName: entry.item.name,
                    repository: context.repository,
                    onDone: { state.playlistEntry = nil }
                )
            }
            .sheet(item: $state.editEntry) { entry in
                if let client = context.app?.client {
                    EditMetadataSheet(
                        itemId: entry.item.id, repository: context.repository,
                        client: client,
                        onDone: { changed in
                            state.editEntry = nil
                            // No wait here, unlike a scrape: an edit is applied by the
                            // time the request returns, so the row is already correct.
                            if changed {
                                Task { await context.refreshRow(entry.item.id) }
                            }
                        }
                    )
                }
            }
    }

    @ViewBuilder
    private func artworkPicker(_ context: EntryActionContext) -> some View {
        if let itemId = state.artworkPickerItem, let app = context.app,
           let client = app.client {
            ArtworkPickerSheet(
                itemId: itemId,
                client: client,
                onDone: { changed in
                    state.artworkPickerItem = nil
                    if changed {
                        Task {
                            await app.refreshMetadata(itemId: itemId, replaceEverything: false)
                            await context.refreshRow(itemId)
                        }
                    }
                }
            )
        }
    }
}
