import Foundation
import GRDB

public extension LibraryRepository {

    /// Whole-code matching on the newline-joined column, as `studioMatchSQL`
    /// does — the same needle (`studioPattern`) works for a code.
    static let countryMatchSQL =
        #"(CHAR(10) || item.countries || CHAR(10)) LIKE ? ESCAPE '\'"#

    /// Which countries a library's titles come from, and how many from each —
    /// the picker offers only countries with something behind them.
    func countryTallies(
        types: [JellyfinItem.ItemType] = [],
        libraryId: String? = nil
    ) async throws -> [GenreTally] {
        let privacy = libraryId == nil ? privacyFilter() : nil
        let rows: [String] = try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                .filter(Column("countries") != nil)
            if let privacy { request = request.filter(sql: privacy) }
            if let libraryId { request = request.filter(Column("libraryId") == libraryId) }
            if !types.isEmpty {
                request = request.filter(types.map(\.rawValue).contains(Column("type")))
            }
            return try String.fetchAll(db, request.select(Column("countries")))
        }
        var counts: [String: Int] = [:]
        for row in rows {
            for code in Set(row.components(separatedBy: "\n")) where !code.isEmpty {
                counts[code, default: 0] += 1
            }
        }
        return counts
            .map { GenreTally(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// A code in the viewer's language — "JP" is "Japan" here, "Japon" in
    /// French. An unknown code is shown as itself.
    nonisolated static func countryName(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }
}
