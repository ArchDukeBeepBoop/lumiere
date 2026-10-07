import Foundation
import LumiereKit

/// Keeping a detail page honest while it is open.
///
/// The page's own commands already re-read what they changed — `setEpisodeWatched`
/// reloads the strip, `toggleWatched` re-reads the item. What none of them covered
/// is the change that does not come from the page at all: you play an episode, the
/// player closes, and the episode you just watched still shows as unwatched
/// because nothing told the page underneath. Leaving and coming back fixed it,
/// which is the tell — the data was right, the page was old.
///
/// The same `LibraryChangeFeed` the home screen listens to, for the same reason:
/// the announcement lives with the write, so a page inherits it rather than each
/// new command remembering to re-read. The subscription itself is
/// `View.onLibraryChange`; this is only what this page does about one.
@MainActor
extension DetailModel {

    /// The cheap half of `load()`: what watch state can change, and nothing else.
    ///
    /// Deliberately not `load()`. That re-reads the detail payload, the seasons,
    /// the credits and the related shelf — none of which a tick on an episode can
    /// affect — and doing it on every write would make the page flicker for a
    /// change to one row.
    func refreshFromCache() async {
        entry = try? await repository.entry(id: itemId)
        if isSeries {
            // From the cache only. This runs on every watch-state write under
            // the show, and a server round trip each time is what made a
            // season of ticks crawl.
            if let seasonId = selectedSeasonId,
               let cached = try? await repository.episodes(seriesId: itemId, seasonId: seasonId),
               cached != episodes {
                episodes = cached
            }
            // And the season posters. A season's unwatched corner is drawn
            // from how many episodes under it are unwatched, which is exactly
            // what ticking one changes — and the row held the values it was
            // built with, so the episodes below updated while the poster
            // above them did not. Read from the cache only: the set of
            // seasons cannot change because somebody marked one watched.
            await refreshSeasonsFromCache()
        }
    }

    /// Re-reads the seasons already on screen, keeping the selection.
    func refreshSeasonsFromCache() async {
        guard let fresh = try? await repository.seasons(seriesId: itemId),
              fresh.map(\.id) == seasons.map(\.id)
        else { return }
        seasons = fresh
    }

    /// Redraws the page whenever watch state under it changes in the cache,
    /// whoever wrote it — this page, the player, a sync, another window.
    func observeWatchState() async {
        var isFirst = true
        for await _ in await repository.watchStateChanges(under: itemId) {
            if isFirst { isFirst = false; continue }
            await refreshFromCache()
        }
    }
}
