import Foundation

/// A candidate the *server's own* providers found.
///
/// The important difference from `ProviderMatch`: this needed no API key here. The
/// server already holds credentials for whatever providers its admin configured —
/// TMDB, TheTVDB, OMDb, AniList — and `Items/RemoteSearch/*` asks it to search them
/// on our behalf. `ProviderIds` comes back populated, which is exactly what
/// `RemoteSearch/Apply` wants handed back to it.
public struct RemoteSearchResult: Decodable, Sendable, Identifiable, Hashable {
    public let name: String?
    public let productionYear: Int?
    public let overview: String?
    public let imageURL: String?
    public let searchProviderName: String?
    public let providerIds: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case productionYear = "ProductionYear"
        case overview = "Overview"
        case imageURL = "ImageUrl"
        case searchProviderName = "SearchProviderName"
        case providerIds = "ProviderIds"
    }

    /// Built from the provider ids rather than a server-side identifier, because the
    /// results carry no id of their own — they are search candidates, not items.
    public var id: String {
        let ids = (providerIds ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(name ?? "?")|\(productionYear.map(String.init) ?? "?")|\(ids)"
    }

    public var posterURL: URL? {
        imageURL.flatMap(URL.init(string:))
    }

    /// Memberwise, so a match found through a provider search can be applied through
    /// the same call as one the server returned. Decodable synthesises no public
    /// initialiser, and a second POST to the identify endpoint is a second place for
    /// its timeout and its verification to be got wrong.
    public init(
        name: String?,
        productionYear: Int? = nil,
        overview: String? = nil,
        imageURL: String? = nil,
        searchProviderName: String? = nil,
        providerIds: [String: String]? = nil
    ) {
        self.name = name
        self.productionYear = productionYear
        self.overview = overview
        self.imageURL = imageURL
        self.searchProviderName = searchProviderName
        self.providerIds = providerIds
    }
}

private struct RemoteSearchQuery: Encodable {
    struct SearchInfo: Encodable {
        let Name: String
        let ItemId: String
    }
    let SearchInfo: SearchInfo
    let IncludeDisabledProviders: Bool
}

public extension JellyfinClient {

    /// Searches the server's configured metadata providers.
    ///
    /// This is the path that should be tried first, and the reason is the whole
    /// original design rule: Jellyfin already scrapes with real credentials, so
    /// asking it costs no key here, works out of the box, and returns ids in exactly
    /// the shape `applyProviderMatch` already posts back. The key-based providers in
    /// `ProviderSearch` only earn their place where the server comes back empty —
    /// which for anime it genuinely does.
    func remoteSearch(
        itemId: String,
        name: String,
        isSeries: Bool
    ) async throws -> [RemoteSearchResult] {
        let body = RemoteSearchQuery(
            SearchInfo: .init(Name: name, ItemId: itemId),
            // Disabled providers included on purpose: an admin who turned a provider
            // off for automatic scraping still usually wants it available when
            // correcting a match by hand, which is the only thing this is used for.
            IncludeDisabledProviders: true
        )
        return try await send(
            [RemoteSearchResult].self,
            path: "Items/RemoteSearch/\(isSeries ? "Series" : "Movie")",
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
    }

    /// Applies a result the server itself produced.
    ///
    /// Posts the whole result back rather than picking one id out of it: the server
    /// accepts its own `RemoteSearchResult` shape, and handing back every provider id
    /// it found lets it scrape from all of them instead of just the one we guessed
    /// was primary.
    func applyRemoteSearchResult(itemId: String, result: RemoteSearchResult) async throws {
        var body: [String: Any] = ["ProviderIds": result.providerIds ?? [:]]
        if let name = result.name { body["Name"] = name }
        if let year = result.productionYear { body["ProductionYear"] = year }
        if let provider = result.searchProviderName { body["SearchProviderName"] = provider }
        if let image = result.imageURL { body["ImageUrl"] = image }

        do {
            try await sendVoid(
                path: "Items/RemoteSearch/Apply/\(itemId)",
                method: "POST",
                query: [URLQueryItem(name: "replaceAllImages", value: "true")],
                body: try JSONSerialization.data(withJSONObject: body),
                // Minutes, not the default minute. This endpoint re-matches the
                // item against the provider and downloads every image it offers
                // before it answers — on a series with a full artwork set that is
                // routinely longer than a read ever is.
                timeout: 600
            )
        } catch let error as JellyfinError {
            // A dropped connection here is not evidence of failure.
            //
            // Reported as "the network connection was lost" while the identify had
            // in fact worked: the server was still scraping, the socket went away,
            // and the app turned a transport event into a claim about the outcome.
            // The only honest answer is to go and look.
            //
            // Matched on JellyfinError, not URLError: `execute` wraps every
            // transport failure into `.notReachable` before it reaches here, so a
            // URLError clause looks right, compiles, and never once fires.
            guard case .notReachable(let underlying) = error else { throw error }
            Diagnostics.log("[identify] apply lost the connection (\(underlying)); verifying")
            guard try await hasProviderIds(result.providerIds ?? [:], on: itemId) else {
                throw error
            }
        }
    }

    /// Whether an item now carries the ids that were just applied.
    ///
    /// Retried, because the scrape is often still finishing when the socket drops —
    /// asking once would report the very case this exists for as a failure.
    private func hasProviderIds(_ expected: [String: String], on itemId: String) async throws -> Bool {
        guard !expected.isEmpty else { return false }

        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }

            guard let data = try? await sendData(
                path: "Users/\(session.userId)/Items/\(itemId)",
                query: [URLQueryItem(name: "Fields", value: FieldSet.detail.value)]
            ), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if ProviderIdMatch.matches(
                expected: expected, actual: ProviderIdMatch.providerIds(in: object)
            ) { return true }
        }
        return false
    }
}
