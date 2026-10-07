import Foundation

/// One episode's still, as TMDB names it.
public struct EpisodeStill: Sendable, Equatable {
    public let season: Int
    public let episode: Int
    /// A full URL on TMDB's image host, ready to hand to the server.
    public let imageURL: String
}

/// Fetches episode stills from TMDB for a series whose id is already known.
///
/// The key stays in the client, as identify's does: the server never holds a
/// third-party credential. What crosses to the server is a list of picture URLs
/// on a host it will check against its own allowlist.
public enum EpisodeStillFetch {

    /// The size to ask TMDB for.
    ///
    /// `w780` rather than `original`: an episode still is drawn at 360pt on the
    /// widest card this app has, so 780 pixels covers a 2x display with room to
    /// spare, and `original` is routinely a 1920-wide JPEG — two and a half times
    /// the bytes for pixels nothing will ever draw.
    public static let stillSize = "w780"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Per season, unattended, behind a progress line — not a search someone
        // is watching a cursor for.
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Every still TMDB lists for one season.
    ///
    /// A season TMDB has never heard of is not an error — a library is full of
    /// "Season Unknown" and of seasons numbered past what aired — so a 404 comes
    /// back as no stills rather than abandoning the seasons after it.
    public static func season(
        tmdbId: String,
        seasonNumber: Int,
        token: String
    ) async throws -> [EpisodeStill] {
        guard let url = URL(
            string: "https://\(MetadataProvider.tmdb.host)/3/tv/\(tmdbId)/season/\(seasonNumber)"
        ) else {
            throw ProviderSearch.SearchError.failed("Bad episode URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderSearch.SearchError.failed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return [] }
            guard (200..<300).contains(http.statusCode) else {
                throw ProviderSearch.SearchError.failed(
                    "TMDB returned \(http.statusCode) for season \(seasonNumber)."
                )
            }
        }
        return try decode(data, seasonNumber: seasonNumber)
    }

    /// Pure, so TMDB's shape can be tested without a network.
    public static func decode(_ data: Data, seasonNumber: Int) throws -> [EpisodeStill] {
        struct Payload: Decodable {
            struct Episode: Decodable {
                let episode_number: Int?
                let season_number: Int?
                let still_path: String?
            }
            let episodes: [Episode]?
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ProviderSearch.SearchError.failed("Unreadable episode list.")
        }

        return (payload.episodes ?? []).compactMap { episode in
            // An episode TMDB has no picture for sends `still_path: null`, which
            // is most of the reason this checks at all: joining a nil path
            // produces a URL that 404s, and the server would log a failure for
            // every episode of every show that simply has no artwork.
            guard let number = episode.episode_number,
                  let path = episode.still_path, !path.isEmpty
            else { return nil }
            return EpisodeStill(
                season: episode.season_number ?? seasonNumber,
                episode: number,
                imageURL: "https://image.tmdb.org/t/p/\(stillSize)\(path)"
            )
        }
    }
}
