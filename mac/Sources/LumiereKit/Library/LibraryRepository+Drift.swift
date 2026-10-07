import Foundation
import GRDB

public extension LibraryRepository {
    /// How many items the cache holds for a library — the number a full read
    /// of it would have written. See `AppModel.checkDrift`.
    func cachedCount(libraryId: String) async -> Int {
        (try? await database.writer.read { db in
            try ItemRecord.filter(Column("libraryId") == libraryId).fetchCount(db)
        }) ?? 0
    }

    /// The server's count for the same read, in one small request.
    func serverCount(libraryId: String) async throws -> Int {
        try await client.items(parentId: libraryId, recursive: true, limit: 1).totalRecordCount
    }

    /// One full read of one library, with its deletion sweep.
    func rereadLibrary(_ libraryId: String) async throws {
        try await syncLibrary(id: libraryId, mode: .full)
    }
}
