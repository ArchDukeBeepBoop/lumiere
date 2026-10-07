import Foundation

public extension LibraryRepository {

    /// What a run of the episode-image fetcher did.
    struct EpisodeImageResult: Sendable {
        public let fetched: Int
        public let considered: Int
        /// Set when the run could not start: no TMDB id, or no key.
        public let blocked: String?
    }

    /// Fills in missing episode stills from TMDB.
    ///
    /// The division of work matches identify: the server says which episodes have
    /// no picture and what it believes the series to be, this asks TMDB for the
    /// stills, and the server fetches and files them. The key never leaves here
    /// and the server never scrapes.
    ///
    /// Seasons are fetched only where an episode of that season is actually
    /// missing a picture — a show with one unscraped season costs one request,
    /// not one per season.
    func fetchEpisodeImages(seriesId: String) async throws -> EpisodeImageResult {
        guard let token = MetadataCredentials.key(for: .tmdb) else {
            return EpisodeImageResult(
                fetched: 0, considered: 0,
                blocked: "No TMDB key. Add one in Settings › Metadata Providers."
            )
        }

        let pending = try await client.pendingEpisodeImages(seriesId: seriesId)
        guard !pending.TmdbId.isEmpty else {
            return EpisodeImageResult(
                fetched: 0, considered: pending.Episodes.count,
                blocked: "This series has no TMDB id. Identify it first."
            )
        }
        guard !pending.Episodes.isEmpty else {
            return EpisodeImageResult(fetched: 0, considered: 0, blocked: nil)
        }

        // season → the episodes of it that need a picture, so a still can be
        // matched back to the item id the server named.
        var wanted: [Int: [Int: String]] = [:]
        for episode in pending.Episodes {
            wanted[episode.SeasonNumber, default: [:]][episode.EpisodeNumber] = episode.Id
        }

        var images: [(itemId: String, url: String)] = []
        for season in wanted.keys.sorted() {
            if Task.isCancelled { break }
            let stills = (try? await EpisodeStillFetch.season(
                tmdbId: pending.TmdbId, seasonNumber: season, token: token
            )) ?? []
            for still in stills {
                // Matched on the season we asked for, not the one the payload
                // states: a special can come back numbered 0 while the library
                // files it under the season it aired in.
                guard let itemId = wanted[season]?[still.episode] else { continue }
                images.append((itemId: itemId, url: still.imageURL))
            }
        }

        guard !images.isEmpty else {
            return EpisodeImageResult(
                fetched: 0, considered: pending.Episodes.count,
                blocked: nil
            )
        }

        let result = try await client.applyEpisodeImages(seriesId: seriesId, images: images)
        if result.fetched > 0 {
            // The cached rows still say the episode has no artwork, and the
            // detail page reads the cache.
            let fresh = try await client.episodes(seriesId: seriesId, seasonId: nil)
            try await cache(items: fresh)
            LibraryChangeFeed.shared.note("episode images", itemId: seriesId)
        }
        return EpisodeImageResult(
            fetched: result.fetched, considered: pending.Episodes.count, blocked: nil
        )
    }
}
