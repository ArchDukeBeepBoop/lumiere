import SwiftUI
import LumiereKit

/// The two things that cover the whole window: the full-size music player and the
/// video player.
///
/// Split from ShellView.swift for the project's 300-line limit. Both are overlays
/// rather than sheets, and for the same reason — a sheet dismisses itself on Escape
/// and on assorted focus changes, which mid-film means losing your place.
extension ShellView {
    @ViewBuilder
    var overlays: some View {
            // Idle on Home: the backdrops. See `ScreensaverHost`.
            ScreensaverHost(app: app, isOnHome: route == .home && path.isEmpty)
                .zIndex(2)

            // The music player at full size, over everything but the video player.
            if app.music.isFullscreen,
               let pipeline = app.imagePipeline,
               let serverURL = app.serverURL {
                FullscreenPlayerView(
                    music: app.music,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    client: app.client,
                    repository: app.repository,
                    onClose: { app.music.isFullscreen = false }
                )
                .transition(.opacity)
            }

            // The player fills the window rather than arriving as a sheet.
            // Sheets dismiss themselves on Escape and on assorted focus changes,
            // which for a video player means losing your place mid-film; and
            // Infuse fills the window too, with its own Close button.
            if let itemId = app.nowPlayingItemId,
               let client = app.client,
               let repository = app.repository,
               let pipeline = app.imagePipeline {
                PlayerView(
                    itemId: itemId,
                    preferredSourceId: app.nowPlayingSourceId,
                    client: client,
                    repository: repository,
                    pipeline: pipeline,
                    capabilities: app.capabilities,
                    mpvAvailable: app.mpvAvailable,
                    mpvReady: { await app.mpvReady() },
                    bridge: bridge,
                    onClose: {
                        app.nowPlayingItemId = nil
                        app.nowPlayingSourceId = nil
                        // Watching something is the commonest way to change what
                        // belongs on the home screen, and nothing was telling it —
                        // Continue Watching sat unmoved until you navigated away
                        // and came back. See `AppModel.contentDidChange`.
                        app.noteContentChanged("after playback")
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
    }
}
