import Foundation
import GRDB

public extension LibraryRepository {
    /// The episodes among `entries` that arrived after their show was last
    /// watched — a new episode of something you are following, rather than
    /// the next of a backlog. Compared in the cache: when the episode was
    /// added against the latest time anything in its show was played.
    func newEpisodeIds(among entries: [LibraryEntry]) async -> Set<String> {
        let episodes = entries.filter { $0.item.itemType == .episode && $0.item.seriesId != nil }
        guard !episodes.isEmpty else { return [] }
        return (try? await database.writer.read { db -> Set<String> in
            var out = Set<String>()
            for entry in episodes {
                guard let seriesId = entry.item.seriesId else { continue }
                let lastWatched = try Date.fetchOne(db, sql: """
                    SELECT max(u.lastPlayedDate) FROM userData u JOIN item e ON e.id = u.itemId
                    WHERE e.seriesId = ? AND u.lastPlayedDate IS NOT NULL
                    """, arguments: [seriesId])
                let added = try Date.fetchOne(db, sql: "SELECT dateCreated FROM item WHERE id = ?",
                                              arguments: [entry.id])
                if let lastWatched, let added, added > lastWatched { out.insert(entry.id) }
            }
            return out
        }) ?? []
    }
}
