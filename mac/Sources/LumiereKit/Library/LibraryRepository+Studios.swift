import Foundation
import GRDB

public extension LibraryRepository {

    /// Whole-studio matching, exactly as `genreMatchSQL` does it: the column is
    /// newline-joined, so wrapping both the column and the needle in newlines is
    /// what stops "Bones" matching a studio called "Bones Inc".
    static let studioMatchSQL =
        #"(CHAR(10) || item.studios || CHAR(10)) LIKE ? ESCAPE '\'"#

    /// The needle for `studioMatchSQL`, escaped for the same reason
    /// `genrePattern` is: a studio name is data, and LIKE reads `%` and `_`.
    static func studioPattern(_ studio: String) -> String {
        "%\n" + escapedForLike(studio) + "\n%"
    }

    /// Shared with `genrePattern`'s escaping rules, kept here so both patterns
    /// cannot drift apart.
    static func escapedForLike(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// Which studios a library holds, and how much of each.
    ///
    /// The same shape as `genreTallies`, over the same cached column format, and
    /// for the same reason: the picker is built from what is actually there, so it
    /// never offers a studio with nothing behind it. Anime and adult are where
    /// this earns its place — both are libraries where the studio is a real way in
    /// rather than a credit, and neither had any way to ask the question.
    func studioTallies(
        types: [JellyfinItem.ItemType] = [],
        libraryId: String? = nil
    ) async throws -> [GenreTally] {
        // Read before the block, as in genreTallies: actor state cannot be touched
        // inside the database's own read closure.
        let privacy = libraryId == nil ? privacyFilter() : nil

        let rows: [String] = try await database.writer.read { [serverId] db in
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                .filter(Column("studios") != nil)
            if let privacy { request = request.filter(sql: privacy) }
            if let libraryId { request = request.filter(Column("libraryId") == libraryId) }
            if !types.isEmpty {
                request = request.filter(types.map(\.rawValue).contains(Column("type")))
            }
            return try String.fetchAll(db, request.select(Column("studios")))
        }

        var counts: [String: Int] = [:]
        for row in rows {
            for studio in Set(row.components(separatedBy: "\n")) where !studio.isEmpty {
                counts[studio, default: 0] += 1
            }
        }

        return counts
            .map { GenreTally(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
