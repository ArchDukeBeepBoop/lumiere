import Foundation

/// An artist or a genre as the Music page's rows draw it: a name, and the
/// picture that stands for it — the artist's photo, or an album's cover
/// where there is none, and for a genre, one of its albums.
public struct MusicCard: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// The item whose Primary image is the picture, and its tag when known.
    public let pictureId: String?
    public let pictureTag: String?

    public init(_ item: JellyfinItem) {
        id = item.id
        name = item.name
        if let tag = item.imageTags?["Primary"] {
            pictureId = item.id
            pictureTag = tag
        } else {
            pictureId = item.albumId
            pictureTag = nil
        }
    }
}

extension JellyfinClient {
    /// A music library's artists, most played first. Empty from a server
    /// without the route.
    func topArtists(parentId: String, limit: Int) async -> [JellyfinItem] {
        (try? await send(ItemsResponse.self, path: "Lumiere/Music/TopArtists", query: [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "Limit", value: String(limit)),
        ]))?.items ?? []
    }
}

public extension LibraryRepository {
    /// The Music page's Top 10 Artists: by plays, then by how many of their
    /// tracks the library holds. Empty from an older server.
    func topArtists(libraryId: String, limit: Int = 10) async -> [MusicCard] {
        await client.topArtists(parentId: libraryId, limit: limit).map(MusicCard.init)
    }

    /// A music library's genres, each with an album of it to picture it.
    func genreCards(libraryId: String) async throws -> [MusicCard] {
        try await client.musicGenres(parentId: libraryId).items.map(MusicCard.init)
    }
}
