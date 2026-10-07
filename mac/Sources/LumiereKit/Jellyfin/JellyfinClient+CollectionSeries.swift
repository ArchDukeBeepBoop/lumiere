import Foundation

/// A collection from the movie database, with the films of it held here.
public struct DiscoveredCollection: Decodable, Sendable, Identifiable {
    public struct Held: Decodable, Sendable {
        public let id: String
        /// The library it is in, as UserViews names it — for the room filter.
        public let library: String
        enum CodingKeys: String, CodingKey { case id = "Id", library = "Library" }
    }
    public let tmdbId: String
    public let name: String
    public let overview: String?
    public let poster: String?
    public let parts: Int?
    public let held: [Held]
    public var id: String { tmdbId }

    enum CodingKeys: String, CodingKey {
        case tmdbId = "TmdbId", name = "Name", overview = "Overview", poster = "Poster"
        case parts = "Parts", held = "Held"
    }
}

/// Lumiere's server: collections as the movie database's film series.
public extension JellyfinClient {
    func discoverCollections(_ name: String) async throws -> [DiscoveredCollection] {
        try await send([DiscoveredCollection].self, path: "Lumiere/Collections/Discover",
                       query: [URLQueryItem(name: "Name", value: name)])
    }

    /// Identify: this collection is that film series — named, described and
    /// pictured from it, and filled with its films here.
    func identifyCollection(_ id: String, as tmdbId: String) async throws {
        struct Added: Decodable { let Added: Int }
        _ = try await send(Added.self, path: "Lumiere/Collections/\(id)/Series/\(tmdbId)", method: "POST")
    }

    /// Finds the collection's series by itself, then does the same.
    func scanCollection(_ id: String) async throws -> Bool {
        struct Result: Decodable { let Found: Bool }
        return try await send(Result.self, path: "Lumiere/Collections/\(id)/Scan", method: "POST").Found
    }

    /// A new collection of these films, dressed as the series; in the private
    /// room's own library when `inRoom`.
    func createCollection(fromSeries tmdbId: String, itemIds: [String], inRoom: Bool) async throws -> String {
        struct Made: Decodable { let Id: String }
        let body = try JSONSerialization.data(withJSONObject: ["ItemIds": itemIds, "Private": inRoom])
        return try await send(Made.self, path: "Lumiere/SeriesCollections/\(tmdbId)", method: "POST", body: body).Id
    }

    /// The automatic pass, now. Returns how many were made and adopted.
    func findCollections() async throws -> (made: Int, adopted: Int) {
        struct Result: Decodable { let Made: Int; let Adopted: Int }
        let r = try await send(Result.self, path: "Lumiere/Collections/Auto", method: "POST")
        return (r.Made, r.Adopted)
    }
}
