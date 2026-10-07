import Foundation
import GRDB

struct HiddenCollectionRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hiddenCollection"

    var itemId: String
    var name: String
    var hiddenAt: Date
    /// The name, lowercased and trimmed. What the id cannot do — see the v17
    /// migration and `HiddenCollections.filterSQL`.
    var nameKey: String?
}

/// A collection the server keeps but Lumiere does not show.
public struct HiddenCollection: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let hiddenAt: Date
}

/// How a hidden collection is matched, in one place.
///
/// By name as well as by id, and the name is the one that matters. Jellyfin's TMDB
/// scraper does not resurrect the BoxSet you deleted — it creates a *new* one, with
/// a new id, on the next library scan. A tombstone holding the old id therefore
/// matches nothing, which is why deleted collections kept coming back however many
/// times they were deleted or hidden.
///
/// Restricted to BoxSets so a film that shares a collection's name is not hidden
/// along with it — "Alien" the film and "Alien Collection" are different rows, but
/// "Harry Potter" is a film *and* a collection on plenty of servers.
public enum HiddenCollections {

    public static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Dropped into every query that lists items. One string, so a new surface
    /// cannot quietly forget it.
    public static var filterSQL: String {
        """
        item.id NOT IN (SELECT itemId FROM hiddenCollection)
        AND (item.type <> 'BoxSet' OR lower(trim(item.name)) NOT IN (
            SELECT nameKey FROM hiddenCollection WHERE nameKey IS NOT NULL
        ))
        """ + (Preference.hidesSingleFilmCollections.value
            // A collection of one is a poster that leads to the same poster.
            // Unknown counts stay: better shown than silently lost.
            ? " AND (item.type <> 'BoxSet' OR COALESCE(item.childCount, 2) > 1)" : "")
    }
}

public extension LibraryRepository {

    /// Stops a collection appearing anywhere in the app.
    ///
    /// The answer to a collection that will not stay deleted. Jellyfin's TMDB
    /// scraper makes one BoxSet per film collection and re-makes them on every
    /// library scan, so deleting is genuinely undone by the server minutes later.
    /// Hiding is the client's own decision and nothing on the server can reverse it.
    func hideCollection(id: String, name: String) async throws {
        try await database.writer.write { db in
            try HiddenCollectionRecord(
                itemId: id, name: name, hiddenAt: Date(),
                nameKey: HiddenCollections.key(for: name)
            ).save(db)
        }
    }

    func unhideCollection(id: String) async throws {
        _ = try await database.writer.write { db in
            try HiddenCollectionRecord.deleteOne(db, key: id)
        }
    }

    /// Everything hidden, newest first, so Settings can offer them back.
    func hiddenCollections() async throws -> [HiddenCollection] {
        let rows: [HiddenCollectionRecord] = try await database.writer.read { db in
            try HiddenCollectionRecord.order(Column("hiddenAt").desc).fetchAll(db)
        }
        return rows.map { HiddenCollection(id: $0.itemId, name: $0.name, hiddenAt: $0.hiddenAt) }
    }

    func clearHiddenCollections() async throws {
        _ = try await database.writer.write { db in
            try HiddenCollectionRecord.deleteAll(db)
        }
    }
}
