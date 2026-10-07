import Foundation
import LumiereKit

/// Noticing content added to the server while the app is open.
///
/// There was no periodic sync at all. The library was read at launch, on
/// reconnection, when playback ended, and when the Refresh button was pressed — so a
/// show added to the server while Lumiere sat open never appeared, however long you
/// left it. Restarting the app was the only way to discover anything, which is not a
/// thing anyone should have to know.
///
/// Deliberately not a push subscription. Jellyfin can notify over a WebSocket, but
/// that is a live connection held open for the life of the session, a reconnect
/// policy, and a second code path that can disagree with the sync about what the
/// library contains. A quiet poll answers the same question with machinery that
/// already exists and already knows how to behave — see `startSync`, which refuses
/// to run during playback and while offline.
@MainActor
extension AppModel {

    /// How long between passes.
    ///
    /// Fifteen minutes, and it is a compromise rather than a preference. An
    /// incremental pass is not free: it reads 400 items per library before the quiet
    /// pages let it stop, which on eleven libraries is a few thousand rows and a few
    /// minutes of the server's attention. Five minutes would mean the server was
    /// almost never left alone; an hour would not feel like discovery.
    private static let autoSyncInterval: Duration = .seconds(15 * 60)

    /// Starts the poll. Safe to call more than once — the old loop is replaced.
    func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.autoSyncInterval)
                guard !Task.isCancelled, let self else { return }
                // Every reason not to run is already `startSync`'s to judge: a sync
                // in flight, playback in progress, the server away. Duplicating any
                // of that here would be a second opinion to keep in step.
                // The change feed keeps the cache current on Lumiere's server;
                // this pass is for a Jellyfin, which has none.
                guard self.isSignedIn, !self.isOffline, !self.feedIsLive else { continue }
                Diagnostics.log("[sync] periodic pass")
                self.startSync(userInitiated: false)
            }
        }
    }

    func cancelAutoSync() {
        cancelChangeWatch()
        cancelChangeFeed()
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }
}
