import SwiftUI
import LumiereKit

/// The destination every poster in the app pushes to.
///
/// One page rather than one per section, which is why it sits here rather than in
/// any of them: a film reached from a shelf, a search result and a collection are
/// the same page, and the navigation stack is shared so the back path is a single
/// history rather than one per tab.
///
/// Split from ShellView.swift for the project's 300-line limit.
extension ShellView {

    @ViewBuilder
    func detailPage(for route: DetailRoute) -> some View {
        if let repository = app.repository,
           let pipeline = app.imagePipeline,
           let serverURL = app.serverURL {
            DetailView(
                itemId: route.itemId,
                focusEpisodeId: route.focusEpisodeId,
                repository: repository,
                pipeline: pipeline,
                serverURL: serverURL,
                capabilities: app.capabilities,
                serverName: app.client?.session.serverName ?? "Library",
                onPlay: { app.nowPlayingItemId = $0 },
                app: app
            )
        }
    }

    /// A genre card's destination. Same shape as `detailPage(for:)` and for the
    /// same reason: the three services it needs only exist once the cache is open
    /// and the server has been reached, and a `navigationDestination` cannot be
    /// conditional on that.
    @ViewBuilder
    func genrePage(for route: GenreRoute) -> some View {
        if let repository = app.repository,
           let pipeline = app.imagePipeline,
           let serverURL = app.serverURL {
            GenreBrowseView(
                genre: route.name,
                isStudio: route.isStudio,
                repository: repository,
                pipeline: pipeline,
                serverURL: serverURL
            )
        }
    }

    /// Everything started and not finished. See `ResumeBrowseView`.
    @ViewBuilder
    func resumePage(_ route: ResumeRoute) -> some View {
        Group {
            if let repository = app.repository,
               let pipeline = app.imagePipeline,
               let serverURL = app.serverURL {
                ResumeBrowseView(
                    shelf: route.shelf,
                    repository: repository, pipeline: pipeline, serverURL: serverURL
                )
            }
        }
    }

    /// Everything with an episode waiting. See `NextUpBrowseView`.
    @ViewBuilder
    var nextUpPage: some View {
        if let repository = app.repository,
           let pipeline = app.imagePipeline,
           let serverURL = app.serverURL {
            NextUpBrowseView(
                repository: repository, pipeline: pipeline, serverURL: serverURL
            )
        }
    }

    /// The fifty most recent additions to one library.
    @ViewBuilder
    func latestPage(for route: LatestRoute) -> some View {
        if let repository = app.repository,
           let pipeline = app.imagePipeline,
           let serverURL = app.serverURL {
            LatestBrowseView(
                libraryId: route.libraryId,
                libraryName: route.libraryName,
                repository: repository,
                pipeline: pipeline,
                serverURL: serverURL
            )
        }
    }

    /// A cast member's destination. Same three services, same reason as above.
    @ViewBuilder
    func personPage(for route: PersonRoute) -> some View {
        if let repository = app.repository,
           let pipeline = app.imagePipeline,
           let serverURL = app.serverURL {
            PersonView(
                route: route,
                repository: repository,
                pipeline: pipeline,
                serverURL: serverURL
            )
        }
    }
}
