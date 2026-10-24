import Foundation
import GRDB

public extension LibraryRepository {

    /// Up Next for files on this Mac: for each folder watched lately, the file
    /// after the furthest one watched — a season on disk carried on the way
    /// Apple TV carries on a show. Folders with a file half-watched are left
    /// to Continue, which already has it.
    func localUpNext(limit: Int = 12) async throws -> [LibraryEntry] {
        let parents: [String] = try await database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT item.parentId FROM item
                JOIN userData ON userData.itemId = item.id
                WHERE item.serverId = ? AND item.isFolder = 0 AND item.parentId IS NOT NULL
                  AND (userData.played = 1 OR userData.playbackPositionTicks > 0)
                GROUP BY item.parentId
                ORDER BY MAX(COALESCE(userData.lastPlayedDate, userData.updatedAt)) DESC
                LIMIT ?
                """, arguments: [LocalLibrary.serverId, limit * 2])
        }
        var result: [LibraryEntry] = []
        for parent in parents {
            guard let first = try await entries(parentId: parent, types: [.video, .audio], limit: 1).first,
                  let next = Self.nextUnwatched(in: try await localSiblings(of: first.id))
            else { continue }
            result.append(next)
            if result.count == limit { break }
        }
        return result
    }

    /// The first unwatched, unstarted file after the furthest watched one, in
    /// folder order. Nil when one is mid-way (Continue has it) or all are done.
    static func nextUnwatched(in siblings: [LibraryEntry]) -> LibraryEntry? {
        if siblings.contains(where: { ($0.userData?.playbackPositionTicks ?? 0) > 0 && $0.userData?.played != true }) {
            return nil
        }
        let lastWatched = siblings.lastIndex { $0.userData?.played == true } ?? -1
        return siblings.dropFirst(lastWatched + 1).first { $0.userData?.played != true }
    }
}
