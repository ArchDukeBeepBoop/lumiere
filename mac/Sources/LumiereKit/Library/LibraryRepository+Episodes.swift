import Foundation
import GRDB

/// A series' seasons and episodes, cached-then-revalidated.
///
/// Split from LibraryRepository+Detail.swift for the project's 300-line rule, and
/// they belong together anyway: both serve the cache first so a page opens
/// instantly, and both must then ask the server, because the cached answer is the
/// one that goes stale when a new episode lands.
public extension LibraryRepository {

    /// - Parameter allowingCache: false forces the server. Same staleness as
    ///   `episodes` below and for the same reason — a series whose seasons were
    ///   cached once never asked again, so a whole new season could not appear.
    func seasons(
        seriesId: String, allowingCache: Bool = true
    ) async throws -> [LibraryEntry] {
        let cached = try await entries(
            parentId: seriesId, types: [.season], sort: .title, descending: false, limit: 100
        ).orderedAsSeasons
        if !cached.isEmpty, allowingCache { return try await withEpisodes(cached) }
        // No seasons cached, but episodes filed under the show itself: that is
        // a show with no seasons, and it is the cached answer. Asking the server
        // first held its page on "Loading episodes…" for a round trip — the
        // whole minute of a timeout when the server was away. The page's own
        // revalidation (`allowingCache: false`) still asks straight after.
        if cached.isEmpty, allowingCache, try await hasLooseEpisodes(seriesId: seriesId) { return [] }

        let fetched = try await client.seasons(seriesId: seriesId)
        try await cache(items: fetched)
        let refreshed = try await entries(
            parentId: seriesId, types: [.season], sort: .title, descending: false, limit: 100
        ).orderedAsSeasons
        return try await withEpisodes(refreshed)
    }

    /// - Parameter allowingCache: false forces the server, whatever is cached.
    ///
    ///   The cached branch below returns as soon as it finds anything, which makes a
    ///   second visit instant and made a season permanently stale: once one episode
    ///   was cached the page never asked the server again, so a newly added episode
    ///   only appeared when the incremental sync happened to write it — one at a
    ///   time, and only after leaving the page and coming back. The detail page now
    ///   shows the cached list at once and then calls this again with false, which
    ///   is the revalidation that was missing.
    func episodes(
        seriesId: String, seasonId: String?, allowingCache: Bool = true
    ) async throws -> [LibraryEntry] {
        // No season: every episode filed under the show itself, from the cache
        // first like any season. Specials stay out, as on the server path below.
        if seasonId == nil, allowingCache {
            let cached = try await entries(
                parentId: seriesId, types: [.episode], sort: .title, descending: false, limit: 500
            ).filter { $0.item.parentIndexNumber != 0 }
            if !cached.isEmpty {
                return await withCreditless(
                    cached.orderedAsEpisodes(byFilename: Preference.episodesFollowFilename.value),
                    seriesId: seriesId, seasonId: nil
                )
            }
        }
        if let seasonId, allowingCache {
            let cached = try await entries(
                parentId: seasonId, types: [.episode], sort: .title, descending: false, limit: 500
            )
            if !cached.isEmpty {
                return await withCreditless(
                    cached.orderedAsEpisodes(byFilename: Preference.episodesFollowFilename.value), seriesId: seriesId, seasonId: seasonId
                )
            }
        }

        let fetched = try await client.episodes(seriesId: seriesId, seasonId: seasonId)
        try await cache(items: fetched)

        guard let seasonId else {
            // The "all episodes" case, used when a series has no season rows. Specials
            // are excluded here on purpose: they are supplements, and mixing them into
            // a flat episode list puts an OVA between episodes 6 and 7. They stay
            // reachable through the specials season below.
            let all = try await entries(
                parentId: seriesId, types: [.episode], sort: .title, descending: false, limit: 500
            ).filter { $0.item.parentIndexNumber != 0 }
            return await withCreditless(all, seriesId: seriesId, seasonId: nil)
        }
        let season = try await entries(
            parentId: seasonId, types: [.episode], sort: .title, descending: false, limit: 500
        )
        // Specials come back by name; a numbered season keeps its numbers.
        return await withCreditless(
            season.orderedAsEpisodes(byFilename: Preference.episodesFollowFilename.value), seriesId: seriesId, seasonId: seasonId
        )
    }

    private func hasLooseEpisodes(seriesId: String) async throws -> Bool {
        try await !entries(parentId: seriesId, types: [.episode], sort: .title, descending: false, limit: 1).isEmpty
    }
}
