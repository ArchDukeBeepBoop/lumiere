import Foundation

/// One of TMDB's alternative episode orders for a show — DVD, absolute,
/// production — which the naming pass can follow instead of TMDB's own.
public struct EpisodeGroup: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let type: Int
    public let groupCount: Int
    public let episodeCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description, type
        case groupCount = "group_count", episodeCount = "episode_count"
    }

    /// TMDB's own label for the kind of order.
    public var kindName: String {
        switch type {
        case 1: return "Original air date"
        case 2: return "Absolute"
        case 3: return "DVD"
        case 4: return "Digital"
        case 5: return "Story arc"
        case 6: return "Production"
        case 7: return "TV"
        default: return "Other"
        }
    }
}

public struct EpisodeGroupChoice: Decodable, Sendable {
    public let groups: [EpisodeGroup]
    /// The chosen group's id, or "" for TMDB's own order.
    public let selected: String
    /// Group id → how well its parts match the season folders, 0–1. Absent
    /// from an older server.
    public let fits: [String: Double]?

    enum CodingKeys: String, CodingKey { case groups = "Groups", selected = "Selected", fits = "Fits" }

    /// The order that fits the folders best, where one clearly does.
    public var bestFit: String? {
        guard let (id, score) = fits?.max(by: { $0.value < $1.value }), score >= 0.5 else { return nil }
        return id
    }
}

public extension JellyfinClient {
    func episodeGroups(seriesId: String) async throws -> EpisodeGroupChoice {
        try await send(EpisodeGroupChoice.self, path: "Shows/\(seriesId)/EpisodeGroups")
    }

    /// Chooses an order ("" for TMDB's own); the server renames the show under it.
    func setEpisodeGroup(seriesId: String, groupId: String) async throws {
        try await sendVoid(
            path: "Shows/\(seriesId)/EpisodeGroup",
            body: try JSONSerialization.data(withJSONObject: ["Id": groupId])
        )
    }
}

public extension LibraryRepository {
    func episodeGroups(seriesId: String) async throws -> EpisodeGroupChoice {
        try await client.episodeGroups(seriesId: seriesId)
    }

    func setEpisodeGroup(seriesId: String, groupId: String) async throws {
        try await client.setEpisodeGroup(seriesId: seriesId, groupId: groupId)
    }
}
