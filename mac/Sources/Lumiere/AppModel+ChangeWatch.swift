import AppKit
import LumiereKit

/// Noticing changes made on the server by someone other than this app.
///
/// The periodic sync in `AppModel+AutoSync` runs every fifteen minutes, so an
/// episode ticked off on another device, a scan that found new files, or a repair
/// pass reached the home screen up to fifteen minutes late. Reported twice as
/// "the home screen updates late after changes behind the scenes".
///
/// The server now publishes a change marker — row counts and the newest write
/// time — on its status endpoint. Reading it is two counts, so it can be asked
/// often; the sync, which is not cheap, runs only when the marker has moved.
@MainActor
extension AppModel {

    /// The loop and the last marker seen. Held here rather than on `AppModel`,
    /// which is at the line budget.
    @MainActor private enum ChangeWatch {
        static var task: Task<Void, Never>?
        static var lastMarker: String?
    }

    /// Starts the watch. Safe to call more than once — the old loop is replaced.
    func startChangeWatch() {
        ChangeWatch.task?.cancel()
        ChangeWatch.lastMarker = nil
        ChangeWatch.task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let seconds = Preference.changeCheckSeconds.value
                // In the background, every two minutes at most: nobody is
                // looking at the home screen, and the server is left alone.
                let pace = NSApp.isActive ? seconds : max(seconds, 120)
                // Off: look again for the setting in a minute, do nothing else.
                try? await Task.sleep(for: .seconds(seconds > 0 ? pace : 60))
                guard !Task.isCancelled, let self else { return }
                guard seconds > 0, self.isSignedIn, !self.isOffline, !self.feedIsLive else { continue }
                await self.checkForServerChanges()
            }
        }
    }

    func cancelChangeWatch() {
        ChangeWatch.task?.cancel()
        ChangeWatch.task = nil
    }

    private func checkForServerChanges() async {
        guard let marker = (try? await client?.serverScanStatus())?.Changed,
              !marker.isEmpty else { return }
        defer { ChangeWatch.lastMarker = marker }
        // The first reading is a baseline: launch has just synced.
        guard let last = ChangeWatch.lastMarker, last != marker else { return }
        Diagnostics.log("[sync] the server changed — syncing now")
        // `startSync` refuses during playback and while one is running; a
        // refused pass is caught by the next marker check or the periodic sync.
        startSync(userInitiated: false)
    }
}
