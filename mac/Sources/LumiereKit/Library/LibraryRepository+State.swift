import Foundation
import GRDB

/// When each library was last read, and how completely.
///
/// Split from LibraryRepository.swift for the project's 300-line limit. Its own
/// concern anyway: everything else there answers "what is in the library", where
/// this answers "how current is what we hold" — which is what decides whether a
/// routine sync can be incremental or a full scan is overdue.
extension LibraryRepository {

    // MARK: - Sync bookkeeping

    // Not private: LibraryRepository+Sync.swift records the last-sync stamp.
    func setSyncState(key: String, value: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO syncState (key, value, updatedAt) VALUES (?, ?, ?) "
                   + "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
                arguments: [key, value, Date()]
            )
        }
    }

    // Not private: LibraryRepository+Sync.swift reads the full-scan stamp.
    func syncState(key: String) async throws -> String? {
        try await database.writer.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [key]
            )
        }
    }

    public func lastSync(libraryId: String) async throws -> Date? {
        try await database.writer.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM syncState WHERE key = ?",
                arguments: ["library.\(libraryId)"]
            ) else { return nil }
            return ISO8601DateFormatter().date(from: value)
        }
    }
}
