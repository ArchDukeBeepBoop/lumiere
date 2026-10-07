import Foundation
import GRDB

public extension LibraryRepository {
    /// What was finished, newest first — "what was that film last month?"
    /// answered without remembering its name. Played items with a known date.
    func watchedRecently(limit: Int = 200) async throws -> [LibraryEntry] {
        let privacy = privacyFilter()
        return try await database.writer.read { [serverId] db in
            let watched = TableAlias()
            var request = ItemRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("extraType") == nil)
                .filter(sql: HiddenCollections.filterSQL)
                .including(required: ItemRecord.userDataAssociation.aliased(watched)
                    .filter(Column("played") == true)
                    .filter(Column("lastPlayedDate") != nil))
                .order(watched[Column("lastPlayedDate")].desc)
                .limit(limit)
            if let privacy { request = request.filter(sql: privacy) }
            return try LibraryEntry.fetchAll(db, request)
        }
    }
}
