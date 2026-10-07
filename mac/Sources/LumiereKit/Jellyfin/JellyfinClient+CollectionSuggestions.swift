import Foundation

/// A film series the server found, from the movie database's collections.
/// Lumiere's server only; a real Jellyfin answers 404 and there are none.
public struct ServerCollectionSuggestion: Decodable, Sendable {
    public struct MissingFilm: Decodable, Sendable {
        public let Title: String
        public let Year: Int?
    }
    public let Name: String
    public let TmdbId: String
    public let CollectionId: String?
    public let AddIds: [String]?
    public let HeldCount: Int
    public let Missing: [MissingFilm]?
}

public extension JellyfinClient {
    func collectionSuggestions() async -> [ServerCollectionSuggestion] {
        (try? await send([ServerCollectionSuggestion].self, path: "Lumiere/Collections/Suggestions")) ?? []
    }
}
