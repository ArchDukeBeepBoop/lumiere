import Foundation
import LumiereKit

/// Listening for cache writes, so the shelves follow them without being told.
///
/// The other half of `LibraryChangeFeed`. Every write to watch state, favourites or
/// the hidden list now announces itself from inside the repository; this is the one
/// place that hears it and re-reads the home screen.
///
/// Why this exists at all is worth keeping: the refresh used to be wired per surface,
/// so whether Continue Watching noticed you had marked something watched depended on
/// which screen you did it from. From the home row it did. From the See All page,
/// the library grid, a search result, a detail page, a folder wall or either batch
/// bar it did not — the list sat there showing something you had just finished.
@MainActor
extension AppModel {

    /// How long to wait for the writes to stop before re-reading.
    ///
    /// Batch commands are the reason. "Mark 40 episodes watched" is forty writes and
    /// forty announcements, and a refresh each would be forty full passes over every
    /// shelf while the writes are still going — the last of them the only one whose
    /// answer is right. A short quiet period collapses a batch into one refresh and
    /// is imperceptible for a single click.
    private static let settleDelay: Duration = .milliseconds(350)
    /// See `RefreshGate`.
    private static let homeGate = RefreshGate()

    /// Starts the listener. Safe to call more than once — the old one is replaced.
    func startLibraryChangeListener() {
        libraryChangeTask?.cancel()
        libraryChangeTask = Task { @MainActor [weak self] in
            let events = await LibraryChangeFeed.shared.events()
            for await change in events {
                guard let self else { return }
                // A collection someone deleted: the one Undo for all seven
                // places that can delete one. See `DeletedCollections`.
                if change.reason == DeletedCollections.reason {
                    self.report("Collection deleted.") { [weak self] in
                        guard let repository = self?.repository else { return }
                        _ = try? await repository.restoreDeletedCollection()
                    }
                }
                // The one card at once; the whole screen after the settle.
                if let itemId = change.itemId {
                    let heard = Date()
                    Task { @MainActor [weak self] in await self?.homeModel?.patch(itemId: itemId, since: heard) }
                }
                // The settle is still cancelled by a newer change — a batch of
                // forty writes waits for its last — but a refresh that has
                // started is never thrown away; the gate queues one more.
                self.pendingChangeTask?.cancel()
                self.pendingChangeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: Self.settleDelay)
                    guard !Task.isCancelled else { return }
                    Task { @MainActor [weak self] in
                        await Self.homeGate.request { [weak self] in
                            await self?.contentDidChange("after \(change.reason)")
                        }
                    }
                }
            }
        }
    }
}
