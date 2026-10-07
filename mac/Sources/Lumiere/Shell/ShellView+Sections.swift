import SwiftUI
import LumiereKit

/// What the detail column shows for each sidebar route.
///
/// Split out of ShellView.swift for the project's 300-line limit, which it
/// crossed again when the sidebar's visibility state moved in. This is the one
/// place that knows a library can be browsed three different ways, and the
/// home screen's library cards route through it exactly as the sidebar rows do.
extension ShellView {

    /// Per-library overrides of the folder/grid default, as comma-joined ids. A
    /// set in AppStorage needs encoding, and two small strings are less machinery
    /// than a codable wrapper for something the user toggles rarely.
    var folderModeLibraries: Set<String> {
        Set(folderModeRaw.split(separator: ",").map(String.init))
    }
    var gridModeLibraries: Set<String> {
        Set(gridModeRaw.split(separator: ",").map(String.init))
    }

    @ViewBuilder
    func sections(
        repository: LibraryRepository,
        pipeline: ImagePipeline,
        serverURL: URL
    ) -> some View {
        switch route {
            case .home:
                HomeView(
                    repository: repository,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    capabilities: app.capabilities,
                    layout: homeLayout,
                    libraries: app.visibleLibraries,
                    app: app,
                    serverName: app.client?.session.serverName ?? "Library",
                    onOpenLibrary: { route = .library(id: $0.id, name: $0.name) },
                    // Pushed onto the shared stack, so Back returns to the shelf.
                    onSeeAllLatest: {
                        path.append(LatestRoute(libraryId: $0.id, libraryName: $0.name))
                    },
                    onSeeAllResume: { path.append(ResumeRoute()) },
                    onSeeAllForgotten: { path.append(ResumeRoute(shelf: .forgotten)) },
                    onSeeAllNextUp: { path.append(NextUpRoute()) }
                )
            case .library(let id, let name):
                // Music and playlists first: nothing about them is in the local cache,
                // so both browsers below — which read cached rows only — would show
                // them as empty. This one asks the server per screen instead.
                if app.libraries.first(where: { $0.id == id })?.holdsPlayableVideo == false {
                    ServerBrowserView(
                        libraryId: id,
                        title: name,
                        repository: repository,
                        pipeline: pipeline,
                        serverURL: serverURL,
                        onPlay: { app.nowPlayingItemId = $0 },
                        // Audio goes to the music queue, not the full-window video
                        // player. Everything else in a playlist — a film, an episode —
                        // still opens the player it needs.
                        onPlayAudio: { entries, index in
                            app.music.play(entries, startingAt: index)
                        },
                        collectionType: app.libraries.first { $0.id == id }?.collectionType,
                        app: app
                    )
                    .id(id)
                }
                // Folder browsing for libraries Jellyfin never identified — a grid of
                // untitled files is worse than the folders they came in. Overridable,
                // since a mixed library can go either way.
                else if folderModeLibraries.contains(id)
                    || (app.libraries.first { $0.id == id }?.prefersFolderBrowsing == true
                        && !gridModeLibraries.contains(id)) {
                    FolderBrowserView(
                        libraryId: id,
                        title: name,
                        repository: repository,
                        pipeline: pipeline,
                        serverURL: serverURL,
                        onPlay: { itemId, sourceId in
                            app.nowPlayingSourceId = sourceId
                            app.nowPlayingItemId = itemId
                        },
                        app: app
                    )
                    .id(id)
                } else {
                LibraryGridView(
                    libraryId: id,
                    title: name,
                    repository: repository,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    app: app
                )
                .id(id)
                }
            case .favourites:
                FavouritesView(
                    repository: repository,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    app: app
                )
            case .search:
                SearchView(
                    repository: repository,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    app: app
                )
            case .settings:
                SettingsView(app: app, homeLayout: $homeLayout)
        }
    }
}
