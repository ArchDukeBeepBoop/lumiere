import Foundation
import GRDB

/// An anime season — "Fall 2024" — as the industry counts them: by the month
/// a show began. Winter is January to March, spring April to June, summer
/// July to September, fall October to December. Read from each title's
/// premiere date, so no lookup is needed and a film counts by its release.
public struct AnimeSeason: Hashable, Sendable, Identifiable, Comparable {
    public enum Quarter: Int, CaseIterable, Sendable {
        case winter = 1, spring, summer, fall

        public var name: String {
            switch self {
            case .winter: return "Winter"
            case .spring: return "Spring"
            case .summer: return "Summer"
            case .fall: return "Fall"
            }
        }
    }

    public let year: Int
    public let quarter: Quarter

    public init(year: Int, quarter: Quarter) {
        self.year = year
        self.quarter = quarter
    }

    /// The season a date in a month falls in.
    public init?(year: Int, month: Int) {
        guard (1...12).contains(month), let quarter = Quarter(rawValue: (month - 1) / 3 + 1) else { return nil }
        self.init(year: year, quarter: quarter)
    }

    /// "2024-4", what a filter stores.
    public var id: String { "\(year)-\(quarter.rawValue)" }

    public init?(id: String) {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, let quarter = Quarter(rawValue: parts[1]) else { return nil }
        self.init(year: parts[0], quarter: quarter)
    }

    /// "Fall 2024".
    public var title: String { "\(quarter.name) \(year)" }

    public static func < (a: AnimeSeason, b: AnimeSeason) -> Bool {
        (a.year, a.quarter.rawValue) < (b.year, b.quarter.rawValue)
    }

    /// The season's months, as a clause over `item.premiereDate` (stored as
    /// "yyyy-MM-dd …", so a string comparison is a date comparison).
    public var filterSQL: String { "(item.premiereDate >= ? AND item.premiereDate < ?)" }

    public var arguments: StatementArguments {
        let first = (quarter.rawValue - 1) * 3 + 1
        let end = quarter == .fall ? String(format: "%04d-01-01", year + 1)
                                   : String(format: "%04d-%02d-01", year, first + 3)
        return [String(format: "%04d-%02d-01", year, first), end]
    }
}

public extension LibraryRepository {
    /// The seasons a library's titles began in, newest first — the Season
    /// filter's choices, so it never offers a season with nothing in it.
    func animeSeasons(libraryId: String, types: [JellyfinItem.ItemType]) async throws -> [AnimeSeason] {
        let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
        let months: [String] = try await database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT substr(premiereDate, 1, 7) FROM item
                WHERE libraryId = ? AND premiereDate IS NOT NULL AND extraType IS NULL
                \(types.isEmpty ? "" : "AND type IN (\(typeList))")
                """, arguments: [libraryId])
        }
        let seasons = Set(months.compactMap { month -> AnimeSeason? in
            let parts = month.split(separator: "-").compactMap { Int($0) }
            return parts.count == 2 ? AnimeSeason(year: parts[0], month: parts[1]) : nil
        })
        return seasons.sorted(by: >)
    }
}
