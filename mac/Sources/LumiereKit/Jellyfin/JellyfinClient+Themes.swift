import Foundation

/// A theme collection on Lumiere's server: films and shows gathered by what
/// they are about, from the movie database's keywords.
public struct CollectionTheme: Codable, Sendable, Identifiable, Hashable {
    public var slug: String
    public var name: String
    public var keywords: [String]
    public var genres: [String]?
    public var enabled: Bool
    public var custom: Bool
    public var count: Int?

    public var id: String { slug.isEmpty ? name : slug }

    public init(name: String, keywords: [String]) {
        self.slug = ""
        self.name = name
        self.keywords = keywords
        self.genres = nil
        self.enabled = true
        self.custom = true
        self.count = nil
    }

    enum CodingKeys: String, CodingKey {
        case slug = "Slug", name = "Name", keywords = "Keywords", genres = "Genres"
        case enabled = "Enabled", custom = "Custom", count = "Count"
    }
}

public extension JellyfinClient {
    private struct ThemeList: Codable, Sendable {
        var themes: [CollectionTheme]
        enum CodingKeys: String, CodingKey { case themes = "Themes" }
    }

    func collectionThemes() async throws -> [CollectionTheme] {
        try await send(ThemeList.self, path: "Lumiere/Collections/Themes").themes
    }

    /// Saves the whole list and builds the collections at once.
    func saveCollectionThemes(_ themes: [CollectionTheme]) async throws {
        let body = try JSONEncoder().encode(ThemeList(themes: themes))
        _ = try await sendData(path: "Lumiere/Collections/Themes", method: "POST", body: body)
    }

    func buildThemeCollections() async throws {
        _ = try await sendData(path: "Lumiere/Collections/Themes/Run", method: "POST")
    }
}
