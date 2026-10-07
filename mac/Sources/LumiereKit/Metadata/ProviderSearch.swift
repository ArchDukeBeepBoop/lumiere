import Foundation

/// A candidate match from a metadata provider.
public struct ProviderMatch: Sendable, Identifiable, Hashable {
    public let provider: MetadataProvider
    /// The provider's own id, which is the only part Jellyfin actually needs.
    public let providerId: String
    public let title: String
    public let originalTitle: String?
    public let year: Int?
    public let overview: String?
    public let posterURL: URL?

    public init(
        provider: MetadataProvider,
        providerId: String,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        posterURL: URL? = nil
    ) {
        self.provider = provider
        self.providerId = providerId
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.posterURL = posterURL
    }

    /// Provider *and* id: the same number means different titles at TMDB and TheTVDB.
    public var id: String { "\(provider.rawValue):\(providerId)" }

    /// What Jellyfin expects in a RemoteSearchResult's ProviderIds.
    public var jellyfinProviderKey: String {
        switch provider {
        case .tmdb: return "Tmdb"
        case .tvdb: return "Tvdb"
        case .myAnimeList: return "AniList"
        case .imdb: return "Imdb"
        }
    }
}

/// Searches a provider for a title, so a wrongly-matched item can be identified.
///
/// The result is deliberately just an *id*. Lumiere does not import metadata itself —
/// it finds the right id and hands it to Jellyfin, which then scrapes with its own
/// providers. That keeps the server authoritative, means every other client sees the
/// correction, and avoids this app maintaining a second, divergent copy of metadata
/// for the same library.
public enum ProviderSearch {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // A search runs while someone waits on it, so it fails fast.
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    public enum SearchError: LocalizedError {
        case noCredential(MetadataProvider)
        case notImplemented(MetadataProvider)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .noCredential(let provider):
                return "No \(provider.title) key. Add one in Settings › Metadata Providers."
            case .notImplemented(let provider):
                return "\(provider.title) search is not implemented yet."
            case .failed(let message):
                return message
            }
        }
    }

    public static func search(
        _ provider: MetadataProvider,
        query: String,
        isSeries: Bool
    ) async throws -> [ProviderMatch] {
        guard let key = MetadataCredentials.key(for: provider) else {
            throw SearchError.noCredential(provider)
        }
        switch provider {
        case .tmdb:
            return try await searchTMDB(query: query, isSeries: isSeries, token: key)
        case .imdb:
            return try await searchOMDB(query: query, isSeries: isSeries, key: key)
        case .tvdb, .myAnimeList:
            // Deliberately explicit rather than silently returning nothing. TheTVDB v4
            // needs a login round-trip to exchange the key for a bearer token, and
            // MyAnimeList's search is OAuth-scoped — each is its own piece of work,
            // and an empty result would read as "no matches" rather than "not built".
            throw SearchError.notImplemented(provider)
        }
    }

    // MARK: - TMDB

    private struct TMDBResponse: Decodable {
        let results: [TMDBResult]?
    }

    private struct TMDBResult: Decodable {
        let id: Int
        let name: String?
        let title: String?
        let originalName: String?
        let originalTitle: String?
        let overview: String?
        let posterPath: String?
        let firstAirDate: String?
        let releaseDate: String?

        enum CodingKeys: String, CodingKey {
            case id, name, title, overview
            case originalName = "original_name"
            case originalTitle = "original_title"
            case posterPath = "poster_path"
            case firstAirDate = "first_air_date"
            case releaseDate = "release_date"
        }
    }

    private static func searchTMDB(
        query: String,
        isSeries: Bool,
        token: String
    ) async throws -> [ProviderMatch] {
        var components = URLComponents(
            string: "https://\(MetadataProvider.tmdb.host)/3/search/\(isSeries ? "tv" : "movie")"
        )
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            // Adult titles included. Without this TMDB silently omits them, which for
            // a personal library is not a safety feature, it is a missing result: the
            // title you are trying to identify is exactly the one being filtered out.
            URLQueryItem(name: "include_adult", value: "true"),
        ]
        guard let url = components?.url else { throw SearchError.failed("Bad search URL.") }

        var request = URLRequest(url: url)
        // v4 read access token, hence Bearer. The v3 key goes in a query parameter
        // instead and is not interchangeable — the commonest mistake here.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SearchError.failed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchError.failed(
                http.statusCode == 401
                    ? "TMDB rejected the token. Check it is the v4 read access token."
                    : "TMDB returned \(http.statusCode)."
            )
        }

        let decoded = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return (decoded.results ?? []).map { result in
            ProviderMatch(
                provider: .tmdb,
                providerId: String(result.id),
                title: result.name ?? result.title ?? "Untitled",
                originalTitle: result.originalName ?? result.originalTitle,
                year: year(from: result.firstAirDate ?? result.releaseDate),
                overview: result.overview,
                posterURL: result.posterPath.flatMap {
                    URL(string: "https://image.tmdb.org/t/p/w342\($0)")
                }
            )
        }
    }

    /// The leading four digits of an ISO date. TMDB sends "" for unknown dates, which
    /// `DateFormatter` would turn into a wrong answer rather than no answer.
    public static func year(from raw: String?) -> Int? {
        guard let raw, raw.count >= 4 else { return nil }
        return Int(raw.prefix(4))
    }

    // MARK: - OMDb (IMDb)

    private struct OMDbSearchResponse: Decodable {
        let search: [OMDbResult]?
        let response: String
        let error: String?

        enum CodingKeys: String, CodingKey {
            case search = "Search"
            case response = "Response"
            case error = "Error"
        }
    }

    private struct OMDbResult: Decodable {
        let title: String
        let year: String?
        let imdbID: String
        let poster: String?

        enum CodingKeys: String, CodingKey {
            case title = "Title"
            case year = "Year"
            case imdbID
            case poster = "Poster"
        }
    }

    private static func searchOMDB(
        query: String,
        isSeries: Bool,
        key: String
    ) async throws -> [ProviderMatch] {
        var components = URLComponents(string: "https://\(MetadataProvider.imdb.host)/")
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: isSeries ? "series" : "movie"),
        ]
        guard let url = components?.url else { throw SearchError.failed("Bad search URL.") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: URLRequest(url: url))
        } catch {
            throw SearchError.failed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchError.failed("OMDb returned \(http.statusCode).")
        }

        let decoded = try JSONDecoder().decode(OMDbSearchResponse.self, from: data)
        guard decoded.response == "True" else {
            // OMDb answers 200 with Response:"False" both for "no matches" and for a
            // rejected key, distinguishable only by the Error text — "Movie not
            // found!" is a normal empty result, an invalid key is the one case
            // actually worth surfacing.
            if let error = decoded.error, error.localizedCaseInsensitiveContains("key") {
                throw SearchError.failed("OMDb rejected the key: \(error)")
            }
            return []
        }

        return (decoded.search ?? []).map { result in
            ProviderMatch(
                provider: .imdb,
                providerId: result.imdbID,
                title: result.title,
                year: year(from: result.year),
                // OMDb's search endpoint carries no synopsis — only its single-title
                // lookup does, which this app has no use for since Jellyfin does the
                // actual metadata fetch once an id is chosen.
                overview: nil,
                posterURL: result.poster.flatMap { $0 == "N/A" ? nil : URL(string: $0) }
            )
        }
    }
}
