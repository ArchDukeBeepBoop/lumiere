import SwiftUI
import LumiereKit

/// The library grid's collection sheets — discover a film series, find
/// collections, smart collections. Split from LibraryGridView.swift for the
/// 300-line rule.
struct CollectionSheets: ViewModifier {
    let grid: LibraryGridView

    func body(content: Content) -> some View {
        content
        // The movie database's film series, gathered from this room's films.
        .sheet(isPresented: grid.$isDiscoveringCollections) {
            if let app = grid.app, let client = app.client {
                CollectionSeriesSheet(
                    mode: .discover, client: client, initialQuery: "",
                    privateLibraryIds: app.privateLibraryIds, inRoom: app.isShowingPrivateLibraries
                ) { changed in
                    grid.isDiscoveringCollections = false
                    if changed { Task { await grid.reload() } }
                }
            }
        }
        .sheet(isPresented: grid.$isEditingSmartCollections) {
            if let client = grid.app?.client {
                SmartCollectionsSheet(client: client) { changed in
                    grid.isEditingSmartCollections = false
                    if changed { Task { await grid.reload() } }
                }
            }
        }
        .sheet(isPresented: grid.$isProposingCollections) {
            RelatedCollectionsSheet(
                libraryId: grid.libraryId,
                libraryName: grid.title,
                repository: grid.repository,
                client: grid.app?.client,
                pipeline: grid.pipeline,
                serverURL: grid.serverURL,
                onDone: { created in
                    grid.isProposingCollections = false
                    // New collections are items in this library, so the grid has to
                    // be re-read to show them.
                    if created { Task { await grid.reload() } }
                }
            )
        }
    }
}
