import Foundation

/// The server's subtitle queue at a glance.
public struct SubtitleQueueStatus: Decodable, Sendable, Equatable {
    public let waiting: Int
    public let done: Int
    public let failed: Int
    public let doneToday: Int
    public let dailyLimit: Int
    /// One line per show. Absent from an older server, hence optional.
    public let shows: [Show]?

    public struct Show: Decodable, Sendable, Equatable, Identifiable {
        public let series: String
        public let waiting: Int
        public let done: Int
        public let failed: Int
        public var id: String { series }

        enum CodingKeys: String, CodingKey {
            case series = "Series", waiting = "Waiting", done = "Done", failed = "Failed"
        }
    }

    enum CodingKeys: String, CodingKey {
        case waiting = "Waiting", done = "Done", failed = "Failed"
        case doneToday = "DoneToday", dailyLimit = "DailyLimit", shows = "Shows"
    }
}

public extension JellyfinClient {
    /// Queues a season's episodes ("" for the whole show) that have no
    /// subtitle in the language. Returns how many were added.
    func queueSubtitles(seriesId: String, seasonId: String, language: String) async throws -> Int {
        struct Added: Decodable, Sendable { let Added: Int }
        return try await send(
            Added.self, path: "Shows/\(seriesId)/Subtitles/Queue", method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["Language": language, "SeasonId": seasonId])
        ).Added
    }

    func subtitleQueueStatus() async throws -> SubtitleQueueStatus {
        try await send(SubtitleQueueStatus.self, path: "Subtitles/Queue")
    }

    /// Puts everything not found back in the queue. Returns how many.
    func retryFailedSubtitles() async throws -> Int {
        struct Retried: Decodable, Sendable { let Retried: Int }
        return try await send(Retried.self, path: "Subtitles/Queue/Retry", method: "POST").Retried
    }

    func setSubtitleDailyLimit(_ limit: Int) async throws {
        try await sendVoid(
            path: "Subtitles/Queue/Limit",
            body: try JSONSerialization.data(withJSONObject: ["DailyLimit": limit])
        )
    }
}

public extension LibraryRepository {
    func queueSubtitles(seriesId: String, seasonId: String, language: String) async throws -> Int {
        try await client.queueSubtitles(seriesId: seriesId, seasonId: seasonId, language: language)
    }
}

/// What has arrived from the subtitle queue since it was last looked at.
public enum SubtitleArrivals {

    public static let seenKey = "subtitleQueueSeen"

    /// A sentence naming the shows with new subtitles, or nil. Pure: `seen`
    /// is each show's fetched count when last announced.
    public static func message(for shows: [SubtitleQueueStatus.Show], seen: [String: Int]) -> String? {
        let fresh = shows.compactMap { show -> (String, Int)? in
            let new = show.done - (seen[show.series] ?? 0)
            return new > 0 ? (show.series, new) : nil
        }
        guard !fresh.isEmpty else { return nil }
        let total = fresh.reduce(0) { $0 + $1.1 }
        let names = fresh.map(\.0)
        let who = names.count == 1 ? names[0]
            : names.count == 2 ? "\(names[0]) and \(names[1])"
            : "\(names[0]) and \(names.count - 1) other shows"
        return "\(total) new subtitle\(total == 1 ? "" : "s") ready for \(who)."
    }
}
