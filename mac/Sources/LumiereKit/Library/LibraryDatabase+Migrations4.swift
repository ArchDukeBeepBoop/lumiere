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

        migrator.registerMigration("v28_item_countries") { db in
            // Where a title comes from, as ISO codes, for the grid's country
            // filter. Filled as the server's change feed carries each title
            // its countries were written for — no full re-read needed.
            try db.alter(table: "item") { t in
                t.add(column: "countries", .text)
            }
        }

        migrator.registerMigration("v29_item_romaji") { db in
            // The romaji title, for the per-library title order. See
            // `LibraryTitleOrder`. Filled as the change feed carries titles
            // the server matched on AniList.
            try db.alter(table: "item") { t in
                t.add(column: "romajiTitle", .text)
            }
        }
    }
}
