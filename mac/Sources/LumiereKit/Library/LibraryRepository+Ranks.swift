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
        // The server's arrangement is the shared one (LibraryRepository+WatchOrder): read it into
        // the local copy, or — the first time, or after a change the server never heard of — send ours.
        let local = try await localRanks(collectionId: collectionId)
        let pending = WatchOrderPending.all().contains(collectionId)
        if let shared = try? await client.watchOrder(collectionId: collectionId) {
            if !pending && !shared.isEmpty {
                try await writeLocalOrder(collectionId: collectionId, itemIds: shared)
                return try await localRanks(collectionId: collectionId)
            }
            if (pending || shared.isEmpty) && !local.isEmpty {
                let ours = local.sorted { $0.value < $1.value }.map(\.key)
                if (try? await client.setWatchOrder(collectionId: collectionId, itemIds: ours)) != nil {
                    WatchOrderPending.clear(collectionId)
                }
            }
        }
        return local
    }

    /// The Mac's own copy of a collection's order.
    private func localRanks(collectionId: String) async throws -> [String: Int] {
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
        try await writeLocalOrder(collectionId: collectionId, itemIds: itemIds)
        // Shared with every other app; unreachable (offline, an older server) it's sent at the next read.
        do { try await client.setWatchOrder(collectionId: collectionId, itemIds: itemIds); WatchOrderPending.clear(collectionId) }
        catch { WatchOrderPending.mark(collectionId) }
    }

    private func writeLocalOrder(collectionId: String, itemIds: [String]) async throws {
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
        do { try await client.setWatchOrder(collectionId: collectionId, itemIds: []); WatchOrderPending.clear(collectionId) }
        catch { WatchOrderPending.mark(collectionId) }
    }
}
