import Foundation
import GRDB

/// Registering, rescanning and removing a folder from this Mac.
///
/// Writes into the same tables as everything else — see `LocalLibrary` for why —
/// under `serverId = "local"`, which is the one condition the Jellyfin sync has to
/// respect and does: every query it runs is scoped to the signed-in server's id.
public extension LibraryRepository {

    /// Adds a folder, or re-reads one already added, and returns what it found.
    ///
    /// Rescanning is a replace rather than a merge: rows under this library that
    /// the walk did not see are files that are no longer on disk, and leaving them
    /// is exactly the "deleted files still show up" problem the Jellyfin side
    /// already had to be fixed for. Watch state is keyed by item id and item ids
    /// are derived from paths, so a file that is still there keeps everything it
    /// had — see `LocalLibrary.id(for:)`.
    @discardableResult
    func scanLocalFolder(at url: URL) async throws -> LocalScanSummary {
        let libraryId = LocalLibrary.libraryId(for: url.path)
        let scanner = LocalLibraryScanner(root: url, libraryId: libraryId)
        let result = scanner.scan()

        try await database.writer.write { db in
            try LibraryRecord(
                id: libraryId,
                serverId: LocalLibrary.serverId,
                name: url.lastPathComponent,
                // No collection type, which is what makes the shell browse it as a
                // folder tree rather than a grid of matched titles — exactly the
                // right shape, and the same one "3D" and "My Videos" already use.
                collectionType: nil,
                // After every Jellyfin library, so adding a folder never rearranges
                // the sidebar someone is used to.
                sortIndex: 1_000,
                itemCount: result.fileCount
            ).save(db)

            let seen = Set(result.records.map(\.id))
            for record in result.records { try record.save(db) }

            let stale = try String.fetchAll(
                db,
                sql: "SELECT id FROM item WHERE libraryId = ?",
                arguments: [libraryId]
            ).filter { !seen.contains($0) }
            for id in stale {
                try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [id])
            }
        }

        return LocalScanSummary(
            libraryId: libraryId,
            name: url.lastPathComponent,
            path: url.path,
            fileCount: result.fileCount,
            unreadable: result.unreadable
        )
    }

    /// Forgets a folder: its rows, its library entry, and the watch state that
    /// only ever described those rows.
    ///
    /// Nothing on disk is touched, and the dialog offering this says so. The watch
    /// state goes because it is meaningless without the items — a row in `userData`
    /// keyed to an item that no longer exists is invisible and permanent.
    func removeLocalLibrary(id libraryId: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM userData WHERE itemId IN "
                   + "(SELECT id FROM item WHERE libraryId = ?)",
                arguments: [libraryId]
            )
            try db.execute(sql: "DELETE FROM item WHERE libraryId = ?", arguments: [libraryId])
            try db.execute(sql: "DELETE FROM library WHERE id = ?", arguments: [libraryId])
        }
    }

    /// Every local folder currently registered.
    func localLibraries() async throws -> [LibraryRecord] {
        try await database.writer.read { db in
            try LibraryRecord
                .filter(Column("serverId") == LocalLibrary.serverId)
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    /// The folder a local library was made from.
    ///
    /// Recovered from the rows rather than stored a second time. Every item under
    /// the library carries its own path, and the library id is a hash of the root,
    /// so the shortest path under it *is* the root or a direct child of it — and
    /// checking the hash tells the two apart with no ambiguity and nothing to keep
    /// in step.
    func localRootPath(libraryId: String) async throws -> String? {
        let paths: [String] = try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT path FROM item WHERE libraryId = ? AND path IS NOT NULL "
                   + "ORDER BY length(path) ASC LIMIT 4",
                arguments: [libraryId]
            )
        }
        for path in paths {
            var url = URL(fileURLWithPath: path)
            // At most a few steps: the shortest path in the library is the root or
            // sits just inside it.
            for _ in 0..<3 {
                url = url.deletingLastPathComponent()
                if LocalLibrary.libraryId(for: url.path) == libraryId { return url.path }
            }
        }
        return nil
    }

    /// The file behind a local item, if it is still there.
    ///
    /// Checked rather than trusted. An external drive that is not mounted leaves
    /// every path intact and every file gone, and a player that spins on a missing
    /// file explains nothing.
    func localFile(for itemId: String) async throws -> URL? {
        guard LocalLibrary.isLocal(itemId: itemId) else { return nil }
        let path: String? = try await database.writer.read { db in
            try String.fetchOne(
                db, sql: "SELECT path FROM item WHERE id = ?", arguments: [itemId]
            )
        }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

public struct LocalScanSummary: Sendable {
    public let libraryId: String
    public let name: String
    public let path: String
    public let fileCount: Int
    public let unreadable: [String]
}
