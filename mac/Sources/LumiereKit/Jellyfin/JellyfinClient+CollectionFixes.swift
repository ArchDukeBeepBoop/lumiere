import Foundation

/// Lumiere's server's collection and naming fixes. See the server's
/// collection_merge.go, collection_fill.go, health_filetitles.go and
/// collection_nextup.go.
public extension JellyfinClient {
    func mergeCollection(_ id: String, into target: String) async throws -> Int {
        struct Merged: Decodable, Sendable { let Added: Int }
        let result = try await send(Merged.self, path: "Lumiere/Collections/\(id)/MergeInto/\(target)", method: "POST")
        Diagnostics.log("[collections] merged \(id) into \(target), \(result.Added) added")
        return result.Added
    }

    /// Minutes of lookups on a first run, hence the long timeout.
    func fillCollections() async throws {
        try await sendVoid(path: "Lumiere/Collections/Fill", method: "POST", timeout: 200)
    }

    func useFileTitles() async throws -> Int {
        struct Renamed: Decodable, Sendable { let Renamed: Int }
        return try await send(Renamed.self, path: "Library/Health/FileTitles", method: "POST").Renamed
    }

    func undoFileTitles() async throws {
        try await sendVoid(path: "Library/Health/FileTitles/Undo", method: "POST")
    }

    /// The next film in each film series under way. Empty from a real Jellyfin.
    func seriesNextUp() async -> [JellyfinItem] {
        (try? await send(ItemsResponse.self, path: "Lumiere/Collections/NextUp",
                         query: [URLQueryItem(name: "Fields", value: FieldSet.list.value)]))?.items ?? []
    }
}

/// A film series the movie database found for a name.
public struct SeriesMatch: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    enum CodingKeys: String, CodingKey { case id = "ID", name = "Name" }
}

public extension JellyfinClient {
    func searchSeries(name: String) async throws -> [SeriesMatch] {
        try await send([SeriesMatch].self, path: "Lumiere/Collections/SeriesSearch",
                       query: [URLQueryItem(name: "Name", value: name)])
    }

    func setSeries(collectionId: String, tmdbId: String) async throws {
        try await sendVoid(path: "Lumiere/Collections/\(collectionId)/Series/\(tmdbId)", method: "POST", timeout: 90)
        Diagnostics.log("[collections] \(collectionId) is film series \(tmdbId)")
    }
}

/// The next film in a film's collection. See the server's NextAfter.
public struct NextInCollection: Decodable, Sendable {
    public let id: String
    public let collection: String
    enum CodingKeys: String, CodingKey { case id = "Id", collection = "Collection" }
}

public extension JellyfinClient {
    func nextInCollection(after itemId: String) async -> NextInCollection? {
        guard let data = try? await sendData(path: "Lumiere/Collections/NextAfter/\(itemId)"),
              !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(NextInCollection.self, from: data)
    }
}

public extension JellyfinClient {
    /// People by name, most-credited first. Empty from a server without it.
    func searchPeople(_ term: String) async -> [JellyfinItem] {
        (try? await send(ItemsResponse.self, path: "Persons",
                         query: [URLQueryItem(name: "searchTerm", value: term),
                                 URLQueryItem(name: "Limit", value: "6")]))?.items ?? []
    }
}
