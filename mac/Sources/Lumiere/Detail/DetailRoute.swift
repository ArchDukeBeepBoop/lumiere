import Foundation
import LumiereKit

/// Identifies a detail page in the navigation stack.
struct DetailRoute: Hashable {
    let itemId: String
    /// Which episode the page should open on, when the thing that was clicked was an
    /// episode but the page being opened is its series.
    ///
    /// Next Up and Continue Watching show episodes, and clicking one used to open
    /// that episode's own page — a dead end with no route to the series it belongs
    /// to, no season strip, and no way to reach the next episode. They now open the
    /// series and name the episode to lead with, which is the page someone actually
    /// wanted.
    var focusEpisodeId: String?

    init(itemId: String, focusEpisodeId: String? = nil) {
        self.itemId = itemId
        self.focusEpisodeId = focusEpisodeId
    }

    /// The route for a card, sending episodes to their series.
    static func forEntry(_ entry: LibraryEntry) -> DetailRoute {
        guard entry.item.itemType == .episode, let seriesId = entry.item.seriesId else {
            return DetailRoute(itemId: entry.id)
        }
        return DetailRoute(itemId: seriesId, focusEpisodeId: entry.id)
    }
}
