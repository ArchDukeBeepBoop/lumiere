import Foundation

/// The episodes a series is missing pictures for, and what the server already
/// knows the series to be.
public struct PendingEpisodeImages: Decodable, Sendable {
    public struct Episode: Decodable, Sendable {
        public let Id: String
        public let SeasonNumber: Int
        public let EpisodeNumber: Int
    }
    /// Empty when the series has never been identified — nothing to look up.
    public let TmdbId: String
    public let Episodes: [Episode]
}

public extension JellyfinClient {

    /// Which episodes of a series have no picture.
    ///
    /// Asked rather than assumed: the client has no idea which episodes already
    /// carry a still, and fetching every season from TMDB to discard most of it
    /// is work nobody needed.
    func pendingEpisodeImages(seriesId: String) async throws -> PendingEpisodeImages {
        try await send(
            PendingEpisodeImages.self,
            path: "Shows/\(seriesId)/EpisodeImages/Pending"
        )
    }

    /// Hands the server the pictures to fetch.
    ///
    /// Returns how many it actually stored. Never the number sent: the server
    /// re-checks what is still missing, and a still that will not download is
    /// skipped rather than failing the run.
    @discardableResult
    func applyEpisodeImages(
        seriesId: String, images: [(itemId: String, url: String)]
    ) async throws -> (fetched: Int, skipped: Int) {
        struct Response: Decodable, Sendable {
            let Fetched: Int
            let Skipped: Int
        }

        let body: [String: Any] = [
            "Images": images.map { ["ItemId": $0.itemId, "ImageUrl": $0.url] }
        ]
        let response = try await send(
            Response.self,
            path: "Shows/\(seriesId)/EpisodeImages",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return (response.Fetched, response.Skipped)
    }
}
