import Foundation
import GRDB

/// The local library cache.
///
/// This exists so browsing is instant and offline-tolerant: the grid reads from
/// SQLite, never from the network, and a background sync reconciles it. It also
/// makes the memory budget achievable — a windowed SQL query returns 60 rows for
/// a 5,000-item library, where holding the server's JSON would not.
///
/// Watch state is authoritative on the server, never here. This cache can be
/// deleted at any time with no loss.
public final class LibraryDatabase: Sendable {

    public let writer: DatabaseWriter

    /// The on-disk location. Caches would be the semantically correct directory,
    /// but macOS may purge it mid-session, and a library re-sync is expensive
    /// enough that Application Support is the better trade.
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Lumiere", isDirectory: true)

        // 0700, and the same argument `TokenStore` already makes one directory
        // over: what is in here is not a secret in the cryptographic sense and is
        // nobody else's business either. `library.db` holds every path in the
        // library, the whole watch history, and the ids of the libraries marked
        // private — a feature whose entire purpose is that certain things do not
        // turn up in front of other people. `Downloads` holds the media itself.
        // World-readable undercut all of it for any other account on this Mac.
        //
        // The directory mode is what does the work: a 0700 directory cannot be
        // walked into whatever the modes of the files inside, which is just as
        // well, since SQLite makes its own -wal and -shm on its own terms.
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Installs made before this line existed were created 0755 and would
        // otherwise stay that way for ever.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: base.path
        )
        return base.appendingPathComponent("library.db")
    }

    public init(url: URL) throws {
        var config = Configuration()
        // WAL plus a pool lets the UI read while a sync writes, which is the whole
        // point of caching locally.
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        config.maximumReaderCount = 4

        writer = try DatabasePool(path: url.path, configuration: config)
        try Self.migrator.migrate(writer)
    }

    /// In-memory instance for tests.
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        writer = try DatabaseQueue()
        try Self.migrator.migrate(writer)
    }

    // The schema itself lives in LibraryDatabase+Migrations.swift.

    // MARK: - Maintenance

    /// Drops every cached row. Used on sign-out and when switching servers —
    /// stale items from another account must never leak into a new session.
    public func reset() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM item")
            try db.execute(sql: "DELETE FROM userData")
            try db.execute(sql: "DELETE FROM library")
            try db.execute(sql: "DELETE FROM syncState")
            try db.execute(sql: "DELETE FROM itemDetail")
            // Item-keyed state derived from an account, and just as wrong to carry
            // into the next one. Every row here is scoped to items that were just
            // deleted, so leaving them behind is not "preserving preferences" —
            // it is orphaned rows waiting for an id collision.
            try db.execute(sql: "DELETE FROM hiddenShelfItem")
            try db.execute(sql: "DELETE FROM trackPreference")
            try db.execute(sql: "DELETE FROM collectionShelfLabel")
            try db.execute(sql: "DELETE FROM collectionRank")
            // Added by later migrations and missed here until an audit found them.
            //
            // `hiddenCollection` is the one that actually bit: it matches BoxSets by
            // *name* rather than by id, deliberately, because the scraper rebuilds a
            // collection under a new id — so a collection hidden on one account stays
            // hidden on the next, with nothing in the UI to explain why a differently
            // owned "Alien Collection" is invisible.
            //
            // `download` rows would otherwise survive pointing at items that no
            // longer exist, and `subtitleOffset` is keyed to item ids that are about
            // to be reused by a different server.
            try db.execute(sql: "DELETE FROM hiddenCollection")
            try db.execute(sql: "DELETE FROM subtitleOffset")
            try db.execute(sql: "DELETE FROM download")
        }
    }

    public func vacuum() async throws {
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }
}
