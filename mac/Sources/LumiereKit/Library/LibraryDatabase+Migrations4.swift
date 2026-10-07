import GRDB

extension LibraryDatabase {
    /// Split from LibraryDatabase+Migrations3.swift for the 300-line limit.
    static func registerNewestMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v27_write_outbox") { db in
            // Watched ticks and favourites made while the server was away. The
            // playback outbox's sibling: kept here, sent on reconnection, and
            // protected from a sync pulling the server's older state over them.
            // One row per item and kind — a later change replaces an earlier one.
            try db.create(table: "writeOutbox") { t in
                t.column("itemId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("value", .boolean).notNull()
                t.column("recordedAt", .datetime).notNull()
                t.primaryKey(["itemId", "kind"])
            }
        }
    }
}
