import Foundation
import LumiereKit

/// Marking a whole season or show, with a way back. See `WatchSnapshot`.
@MainActor
extension AppModel {

    /// Runs a watch-state change; where it touched more than one episode,
    /// offers Undo in the banner. A single film or episode is its own undo —
    /// the same menu item, once more — so it gets no banner at all.
    func changeWatchState(
        of entry: LibraryEntry, watched: Bool, _ change: () async -> Void
    ) async {
        guard let repository,
              UnplayedCount.isContainer(entry.item.itemType),
              let snapshot = try? await repository.watchSnapshot(of: entry.id),
              snapshot.states.count > 1
        else {
            await change()
            return
        }
        await change()
        let what = watched ? "watched" : "unwatched"
        report("\(entry.item.name) marked \(what) — \(snapshot.states.count) episodes.") { [weak self] in
            guard let self else { return }
            if await repository.restore(snapshot) == false {
                self.report("Some episodes could not be put back on the server.")
            }
        }
    }
}
