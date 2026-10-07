import Foundation
import LumiereKit

/// The compact layout's poster wall, and its paging.
///
/// Split from HomeModel.swift for the project's 300-line limit. Unlike the shelves,
/// the wall is a window onto the whole library rather than a fixed handful, so it
/// is the only part of the home screen that pages.
@MainActor
extension HomeModel {

    func loadWall(reset: Bool) async {
        // Before the reset, not after it. The guard used to sit below, so a reset
        // arriving while a page was in flight emptied the wall and then returned at
        // the guard without fetching anything — a blank poster wall that stayed
        // blank until some unrelated action reloaded it.
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        if reset {
            wallOffset = 0
            wallEntries = []
            wallTotal = (try? await repository.count(types: [.movie, .series])) ?? 0
        }

        let page = (try? await repository.entries(
            types: [.movie, .series],
            sort: .dateAdded,
            descending: true,
            limit: wallPageSize,
            offset: wallOffset
        )) ?? []

        wallEntries.append(contentsOf: page)
        wallOffset += page.count
    }

    /// Called when the last few tiles appear. Paging on appearance rather than on
    /// a scroll offset keeps the window of loaded rows bounded no matter how far
    /// down a 5,000-item library you go.
    func loadMoreIfNeeded(currentItem entry: LibraryEntry) async {
        guard wallEntries.count < wallTotal,
              let index = wallEntries.firstIndex(where: { $0.id == entry.id }),
              index >= wallEntries.count - 12 else { return }
        await loadWall(reset: false)
    }
}
