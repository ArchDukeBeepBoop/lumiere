import Foundation
import GRDB

/// A watched tick or a favourite the server has not heard about yet.
public struct WriteOutboxRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "writeOutbox"
    public enum Kind: String, Codable, Sendable { case played, favorite }

    public var itemId: String
    public var kind: Kind
    public var value: Bool
    public var recordedAt: Date
}

public extension LibraryRepository {
    /// Keeps a change made while the server was away, to send on reconnection.
    func enqueueWrite(itemId: String, kind: WriteOutboxRecord.Kind, value: Bool) async {
        try? await database.writer.write { db in
            try WriteOutboxRecord(itemId: itemId, kind: kind, value: value, recordedAt: Date()).save(db)
        }
    }

    func pendingWrites() async -> [WriteOutboxRecord] {
        (try? await database.writer.read { db in
            try WriteOutboxRecord.order(Column("recordedAt")).fetchAll(db)
        }) ?? []
    }

    func clearPendingWrite(_ record: WriteOutboxRecord) async {
        try? await database.writer.write { db in
            // Only if it has not been changed again since it was read.
            try db.execute(sql: "DELETE FROM writeOutbox WHERE itemId = ? AND kind = ? AND recordedAt = ?",
                           arguments: [record.itemId, record.kind.rawValue, record.recordedAt])
        }
    }
}
