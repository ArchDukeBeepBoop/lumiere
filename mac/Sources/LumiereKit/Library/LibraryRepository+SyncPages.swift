import Foundation
import GRDB

/// How a sync pass decides it has seen a page before.
///
/// Split from LibraryRepository+Sync.swift for the project's 300-line rule.
extension LibraryRepository {

    /// Whether every one of these ids is already a cached row.
    ///
    /// The stop condition for an incremental pass. Deliberately id-only: comparing
    /// timestamps would try to detect edits, which this pass cannot see reliably
    /// anyway — a server-side rename does not move an item in DateCreated order, so
    /// pretending otherwise would be a promise the mode cannot keep.
    func isAllCached(_ ids: [String]) async throws -> Bool {
        guard !ids.isEmpty else { return true }
        return try await database.writer.read { db in
            try ItemRecord.filter(ids.contains(Column("id"))).fetchCount(db) == ids.count
        }
    }

    /// When this library was last read in full, which is what decides whether a
    /// routine sync can be incremental.
    public func lastFullSync(libraryId: String) async throws -> Date? {
        guard let raw = try await syncState(key: "library.full.\(libraryId)") else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// Refreshes only watch state, which is all that changes when you watch
    /// something on another device. Far cheaper than a full sync.
    public func refreshWatchState(libraryId: String? = nil) async throws {
        let response = try await client.items(
            parentId: libraryId,
            recursive: true,
            sortBy: ["DatePlayed"],
            sortOrder: .descending,
            limit: 300,
            fields: .list
        )
        let now = Date()
        try await database.writer.write { db in
            for item in response.items {
                // Guarded, and this is the bug that lost watch positions. An item
                // arriving without UserData used to be written as a zeroed record —
                // playbackPositionTicks 0, played false — so every focus of the
                // window quietly erased where you were up to. Absent data means
                // "nothing new to say", never "start from the beginning".
                guard let userData = item.userData else { continue }
                try UserDataRecord(itemId: item.id, from: userData, updatedAt: now)
                    .save(db)
            }
        }
    }
}
