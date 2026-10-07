import Foundation
import GRDB

/// Taking content out of the library, from the cache's side.
///
/// The server does the removing; this forgets the rows locally so the shelves
/// change now rather than at the next full sync. Cascades the way the server
/// does — a show takes its seasons and episodes — because a series tile with
/// no show behind it is exactly the phantom the scanner repairs exist to
/// prevent.
public extension LibraryRepository {

    /// Removes an item from the library. Files are untouched and the item can
    /// be restored from Settings. Returns false if the server refused.
    @discardableResult
    func removeFromLibrary(itemId: String) async -> Bool {
        do {
            try await client.removeFromLibrary(itemId: itemId)
        } catch {
            return false
        }
        await forgetLocally(itemId: itemId)
        return true
    }

    /// Sends the item's files to the Trash and removes it. Throws so the
    /// caller can say *why* — a volume with no Trash is the common refusal.
    func deleteToTrash(itemId: String) async throws {
        try await client.deleteToTrash(itemId: itemId)
        await forgetLocally(itemId: itemId)
    }

    func restore(itemId: String) async throws {
        try await client.restore(itemId: itemId)
        // The restored rows come back through an ordinary refresh; the shelves
        // re-read on the change notice.
        try? await refreshItem(itemId: itemId)
        LibraryChangeFeed.shared.note("restored", itemId: itemId)
    }

    private func forgetLocally(itemId: String) async {
        try? await database.writer.write { db in
            var ids = [itemId]
            var frontier = [itemId]
            while !frontier.isEmpty {
                let children = try ItemRecord
                    .filter(Column("parentId") == frontier[0]
                        || Column("seriesId") == frontier[0]
                        || Column("seasonId") == frontier[0])
                    .fetchAll(db)
                    .map(\.id)
                    .filter { !ids.contains($0) }
                ids.append(contentsOf: children)
                frontier.removeFirst()
                frontier.append(contentsOf: children)
            }
            try ItemRecord.filter(keys: ids).deleteAll(db)
        }
        LibraryChangeFeed.shared.note("removed", itemId: itemId)
    }
}
