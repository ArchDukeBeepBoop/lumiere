import Foundation

/// Smart collections and anime franchises on Lumiere's server. Both are kept
/// current by the server; the app only edits rules and choices. See the
/// server's `api/smart_collections.go` and `api/collection_anilist.go`.

/// One condition: "country is JP", "rating ≥ 8".
public struct SmartRule: Codable, Sendable, Hashable, Identifiable {
    public var field: String
    public var op: String
    public var value: String
    /// Identity for editing in a list; not sent.
    public var id = UUID()

    public init(field: String, op: String, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }

    enum CodingKeys: String, CodingKey { case field = "Field", op = "Op", value = "Value" }
}

/// A smart collection's rules.
public struct SmartRules: Codable, Sendable, Hashable {
    public var match: String
    public var rules: [SmartRule]
    public var sort: String?
    public var limit: Int?

    public init(match: String = "all", rules: [SmartRule] = [], sort: String? = nil, limit: Int? = nil) {
        self.match = match
        self.rules = rules
        self.sort = sort
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey { case match = "Match", rules = "Rules", sort = "Sort", limit = "Limit" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = (try? c.decode(String.self, forKey: .match)) ?? "all"
        rules = (try? c.decode([SmartRule].self, forKey: .rules)) ?? []
        sort = try? c.decode(String.self, forKey: .sort)
        limit = try? c.decode(Int.self, forKey: .limit)
    }
}

public struct SmartCollectionSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let rules: SmartRules
    public let count: Int
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", rules = "Rules", count = "Count" }
}

public struct SmartIdea: Decodable, Sendable, Identifiable, Hashable {
    public let name: String
    public let rules: SmartRules
    public let count: Int
    public var id: String { name }
    enum CodingKeys: String, CodingKey { case name = "Name", rules = "Rules", count = "Count" }
}

public struct SmartPreview: Decodable, Sendable {
    public let count: Int
    public let names: [String]?
    enum CodingKeys: String, CodingKey { case count = "Count", names = "Names" }
}

/// What each field can be set to, from what the library holds.
public struct SmartChoices: Decodable, Sendable {
    public struct Library: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
    }
    public let fields: [String: [String]]
    public let genres: [String]?
    public let countries: [String]?
    public let keywords: [String]?
    public let studios: [String]?
    public let libraries: [Library]?
    enum CodingKeys: String, CodingKey {
        case fields = "Fields", genres = "Genres", countries = "Countries"
        case keywords = "Keywords", studios = "Studios", libraries = "Libraries"
    }
}

public struct AniListStatus: Decodable, Sendable {
    public struct Library: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
        public let on: Bool
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", on = "On" }
    }
    public let libraries: [Library]?
    public let checked: Int
    public let matched: Int
    public let franchises: Int
    public let running: Bool
    /// Franchises wear AniList's key art (and shows borrow the pictures they
    /// lack) rather than a mosaic of posters. Nil from a server before it.
    public let art: Bool?
    enum CodingKeys: String, CodingKey {
        case libraries = "Libraries", checked = "Checked", matched = "Matched"
        case franchises = "Franchises", running = "Running", art = "Art"
    }
}

private struct Items<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]?
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct SavedSmart: Decodable, Sendable {
    let id: String
    let count: Int
    enum CodingKeys: String, CodingKey { case id = "Id", count = "Count" }
}

public extension JellyfinClient {

    func smartCollections() async throws -> [SmartCollectionSummary] {
        try await send(Items<SmartCollectionSummary>.self, path: "Lumiere/SmartCollections").items ?? []
    }

    func smartIdeas() async throws -> [SmartIdea] {
        try await send(Items<SmartIdea>.self, path: "Lumiere/SmartCollections/Ideas").items ?? []
    }

    func smartChoices() async throws -> SmartChoices {
        try await send(SmartChoices.self, path: "Lumiere/SmartCollections/Choices")
    }

    func previewSmart(_ rules: SmartRules) async throws -> SmartPreview {
        let body = try JSONSerialization.data(withJSONObject: ["Rules": try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules))])
        return try await send(SmartPreview.self, path: "Lumiere/SmartCollections/Preview", method: "POST", body: body)
    }

    /// Creates, or with an id updates, a smart collection; returns its id and size.
    @discardableResult
    func saveSmartCollection(id: String?, name: String, rules: SmartRules) async throws -> (id: String, count: Int) {
        var object: [String: Any] = ["Name": name, "Rules": try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules))]
        if let id { object["Id"] = id }
        let saved = try await send(SavedSmart.self, path: "Lumiere/SmartCollections", method: "POST",
                                   body: try JSONSerialization.data(withJSONObject: object))
        return (saved.id, saved.count)
    }

    func aniListStatus() async throws -> AniListStatus {
        try await send(AniListStatus.self, path: "Lumiere/Collections/AniList")
    }

    /// The libraries looked up on AniList, and with `art` whether franchises
    /// wear AniList's key art; a pass starts on the server.
    func setAniListLibraries(_ ids: [String], art: Bool? = nil) async throws {
        var object: [String: Any] = ["Libraries": ids]
        if let art { object["Art"] = art }
        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await sendData(path: "Lumiere/Collections/AniList", method: "POST", body: body)
    }

    /// How each library's franchises are named (see `LibraryTitleOrder.franchiseNaming`);
    /// a pass on the server renames them.
    func setFranchiseNames(_ names: [String: String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["Names": names])
        _ = try await sendData(path: "Lumiere/Collections/AniList/Names", method: "POST", body: body)
    }

    func runAniList() async throws {
        _ = try await sendData(path: "Lumiere/Collections/AniList/Run", method: "POST")
    }
}
