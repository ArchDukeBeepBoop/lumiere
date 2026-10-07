import Foundation

/// The library in a few numbers. See the server's LibraryOverview.
public struct LibraryOverview: Decodable, Sendable {
    public struct File: Decodable, Sendable { public let Name: String; public let Bytes: Int64 }
    public let Films, Shows, Episodes, Videos, Albums, Tracks: Int
    public let Bytes: Int64
    public let WatchedFilms, WatchedEpisodes, AddedThisMonth: Int
    public let Largest: [File]?
}

public extension JellyfinClient {
    func libraryOverview() async -> LibraryOverview? {
        try? await send(LibraryOverview.self, path: "Lumiere/Overview")
    }
}
