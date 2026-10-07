import Foundation
import LumiereKit

/// Loading a series' seasons and episodes, then checking them against the server.
///
/// Split from DetailModel.swift for the project's 300-line rule. The revalidation
/// is the point of both: the cached answer opens the page instantly and is exactly
/// the answer that goes stale the moment a new episode lands.
extension DetailModel {

    func loadSeasons() async {
        seasons = (try? await repository.seasons(seriesId: itemId)) ?? []
        // On the cached path, which is the one that runs. Loading these *after* the
        // revalidation below put them behind its `guard … else { return }`, and that
        // guard returns whenever the season set is unchanged — which is every visit
        // to every series that has not gained a season since the last one. The
        // captions were therefore never populated in the case that is the norm.
        seasonEpisodeCounts =
            (try? await repository.episodeCounts(seriesId: itemId)) ?? [:]
        if selectedSeasonId == nil {
            selectedSeasonId = seasons.first?.id
        }
        await loadEpisodes()

        // Then revalidate, as the episodes do. A series whose seasons were cached
        // once never asked the server again, so an entirely new season could not
        // appear at all. Only reassigned when the set actually differs, and the
        // selection is kept where it still exists so the picker does not jump.
        //
        // Compared whole, not by id. The server's answer is also the one that
        // carries each season's unwatched count, and discarding it whenever the
        // set was unchanged kept a poster on whatever count it was drawn with —
        // a season just ticked watched stayed marked unwatched until something
        // else forced a redraw.
        guard let fresh = try? await repository.seasons(
            seriesId: itemId, allowingCache: false
        ), fresh != seasons else { return }
        let setChanged = fresh.map(\.id) != seasons.map(\.id)
        seasons = fresh
        guard setChanged else { return }
        // Again here, because a season set that just changed is exactly when the
        // counts behind it changed too.
        seasonEpisodeCounts =
            (try? await repository.episodeCounts(seriesId: itemId)) ?? [:]
        if selectedSeasonId == nil || !fresh.contains(where: { $0.id == selectedSeasonId }) {
            selectedSeasonId = fresh.first?.id
            await loadEpisodes()
        }
    }

    func loadEpisodes() async {
        didLoadEpisodes = false
        guard let seasonId = selectedSeasonId else {
            // A show with no seasons at all — short OVAs and the like, filed
            // straight in the show's folder, 103 of them here. This returned an
            // empty strip and the page said "No episodes cached yet" over
            // episodes that were right there; every one of them is the show's.
            episodes = seasons.isEmpty
                ? ((try? await repository.episodes(seriesId: itemId, seasonId: nil)) ?? [])
                : []
            didLoadEpisodes = true
            return
        }
        // Cached first, so the strip is there immediately.
        episodes = (try? await repository.episodes(seriesId: itemId, seasonId: seasonId)) ?? []
        // Set here, not only at the end: the cached answer is a real answer, and
        // the server round trip below can take seconds on a season that will turn
        // out to be empty either way.
        didLoadEpisodes = true

        // Then ask the server, because the cached answer is the one that goes
        // stale. A season whose episodes were cached once was never re-read, so a
        // newly added episode surfaced only as the sync trickled it in — one at a
        // time, and only if you left the page and came back. Reassigned only when
        // it actually differs, so the strip does not flicker on the common case
        // where nothing has changed.
        guard let fresh = try? await repository.episodes(
            seriesId: itemId, seasonId: seasonId, allowingCache: false
        ), fresh.map(\.id) != episodes.map(\.id) else { return }
        episodes = fresh
    }
}
