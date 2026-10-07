import Foundation
import GRDB

struct CollectionRankRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collectionRank"

    var collectionId: String
    var itemId: String
    var rank: Int
    var updatedAt: Date
}

public extension LibraryRepository {

    /// The gap left between ranks, so a title can be moved between two neighbours
    /// without rewriting every row after it.
    static let rankStride = 1_024

    /// A collection's personal order, keyed by item. Empty until you arrange one.
    func collectionRanks(collectionId: String) async throws -> [String: Int] {
        let rows: [CollectionRankRecord] = try await database.writer.read { db in
            try CollectionRankRecord
                .filter(Column("collectionId") == collectionId)
                .fetchAll(db)
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.itemId, $0.rank) })
    }

    /// Writes a whole arrangement at once, spaced by `rankStride`.
    ///
    /// Used when you first switch a collection to personal order — the order you
    /// were looking at becomes the starting point, rather than the list scrambling
    /// into whatever the database happens to return. A personal order that begins
    /// as a shuffle is one nobody will finish arranging.
    func setCollectionOrder(collectionId: String, itemIds: [String]) async throws {
        let now = Date()
        try await database.writer.write { db in
            try CollectionRankRecord
                .filter(Column("collectionId") == collectionId)
                .deleteAll(db)
            for (index, itemId) in itemIds.enumerated() {
                try CollectionRankRecord(
                    collectionId: collectionId,
                    itemId: itemId,
                    rank: (index + 1) * Self.rankStride,
                    updatedAt: now
                ).insert(db)
            }
        }
    }

    /// Moves one title to a position in the collection, 1-based as displayed.
    ///
    /// Takes the whole current order rather than a rank, because "third" is what
    /// someone means and a rank is an implementation detail they should never see.
    /// Rewrites the lot: a collection is tens of items, not thousands, and the
    /// alternative — computing a midpoint rank and renumbering only on collision —
    /// is a second code path that is exercised once a year and wrong when it is.
    func moveInCollection(
        collectionId: String, itemId: String, toPosition position: Int, within order: [String]
    ) async throws {
        var ids = order.filter { $0 != itemId }
        let index = max(0, min(ids.count, position - 1))
        ids.insert(itemId, at: index)
        try await setCollectionOrder(collectionId: collectionId, itemIds: ids)
    }

    /// Forgets the personal order, so the collection reads in whatever order is
    /// chosen next.
    func clearCollectionOrder(collectionId: String) async throws {
        _ = try await database.writer.write { db in
            try CollectionRankRecord
                .filter(Column("collectionId") == collectionId)
                .deleteAll(db)
        }
    }
}
