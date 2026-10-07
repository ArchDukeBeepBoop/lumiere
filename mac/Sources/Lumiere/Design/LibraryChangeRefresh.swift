import SwiftUI
import LumiereKit

/// Keeping an open page honest when something else writes to the cache.
///
/// Every screen that holds its own list of entries goes stale the moment a write
/// happens somewhere else: you play an episode from a grid, come back, and the
/// tick is missing. The page's own commands re-read what they changed — that part
/// was never broken — so the bug only ever appeared for changes the page did not
/// make, which is exactly the case nobody thinks to test.
///
/// A modifier rather than the same loop copied onto nine views. The debounce and
/// the cancellation are decisions worth making once: a burst of writes collapses
/// to one refresh, and the watch ends with the view.
///
/// What to *do* about a change is the page's own business, which is why the
/// closure receives it. A page holding a paged grid should re-read the one row —
/// see `LibraryChange.itemId` — because reloading from offset zero costs the
/// reader their place, which is worse than the stale tick it fixes.
extension View {
    func onLibraryChange(_ handle: @escaping (LibraryChange) async -> Void) -> some View {
        task {
            let events = await LibraryChangeFeed.shared.events()
            for await change in events {
                // Let a burst settle. Marking a season watched is forty writes,
                // and the feed keeps only the newest, so this collapses to one.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await handle(change)
            }
        }
    }
}
