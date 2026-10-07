import Foundation
import GRDB

/// The schema, as an append-only list of numbered migrations.
///
/// Split out of LibraryDatabase.swift because this list only ever grows — every
/// schema change adds to it and none may be edited — so it is the part of that
/// file guaranteed to push it past the 300-line limit again.
extension LibraryDatabase {
    /// Migrations are append-only and numbered. Never edit a shipped migration —
    /// add a new one, so an existing cache upgrades instead of being rebuilt.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_items") { db in
            try db.create(table: "item") { t in
                t.primaryKey("id", .text)
                t.column("serverId", .text).notNull().indexed()
                t.column("type", .text).notNull().indexed()
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull().indexed()

                t.column("parentId", .text).indexed()
                t.column("seriesId", .text).indexed()
                t.column("seriesName", .text)
                t.column("seasonId", .text).indexed()
                t.column("indexNumber", .integer)
                t.column("parentIndexNumber", .integer)

                t.column("overview", .text)
                t.column("productionYear", .integer).indexed()
                t.column("premiereDate", .datetime)
                t.column("dateCreated", .datetime).indexed()
                t.column("officialRating", .text)
                t.column("communityRating", .double)
                t.column("runTimeTicks", .integer)
                t.column("genres", .text)

                t.column("primaryTag", .text)
                t.column("backdropTag", .text)
                t.column("thumbTag", .text)
                t.column("logoTag", .text)
                t.column("parentBackdropItemId", .text)
                t.column("parentBackdropTag", .text)
                t.column("seriesPrimaryImageTag", .text)

                t.column("isFolder", .boolean).notNull().defaults(to: false)
                t.column("collectionType", .text)
                t.column("childCount", .integer)
                t.column("syncedAt", .datetime).notNull()
            }

            // The two orderings every grid uses.
            try db.create(
                index: "item_on_parent_sort",
                on: "item",
                columns: ["parentId", "sortName"]
            )
            try db.create(
                index: "item_on_type_created",
                on: "item",
                columns: ["type", "dateCreated"]
            )
        }

        migrator.registerMigration("v1_user_data") { db in
            // Separate from `item` because watch state changes constantly while
            // metadata almost never does. Writing them together would rewrite a
            // wide row on every progress report.
            try db.create(table: "userData") { t in
                t.primaryKey("itemId", .text)
                t.column("played", .boolean).notNull().defaults(to: false)
                t.column("playbackPositionTicks", .integer).notNull().defaults(to: 0)
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("playedPercentage", .double)
                t.column("unplayedItemCount", .integer)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "userData_on_progress",
                on: "userData",
                columns: ["played", "playbackPositionTicks"]
            )
        }

        migrator.registerMigration("v1_libraries") { db in
            try db.create(table: "library") { t in
                t.primaryKey("id", .text)
                t.column("serverId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("collectionType", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("itemCount", .integer)
            }
        }

        migrator.registerMigration("v1_sync_state") { db in
            try db.create(table: "syncState") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_item_detail") { db in
            // The full server payload for items you have actually opened: media
            // sources, streams, cast, chapters. Stored as JSON rather than
            // columns because it is only ever read whole, and stored at all so a
            // detail page you have seen once still opens with the server asleep.
            //
            // Deliberately not populated by the library sync — caching this for
            // every item would cost hundreds of megabytes.
            try db.create(table: "itemDetail") { t in
                t.primaryKey("itemId", .text)
                t.column("json", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_item_path") { db in
            // Needed by the "original filename" title style. Cached during the
            // normal library sync rather than fetched per item, because a grid
            // showing filenames would otherwise issue one request per cell.
            try db.alter(table: "item") { t in
                t.add(column: "path", .text)
            }
        }

        migrator.registerMigration("v4_downloads") { db in
            // Offline copies. Keyed by item, so an item cannot be queued twice, and
            // storing the local path outright rather than deriving it — a file the
            // user already has on disk must stay findable even if the naming scheme
            // changes later.
            try db.create(table: "download") { t in
                t.primaryKey("itemId", .text)
                t.column("serverId", .text).notNull()
                t.column("state", .text).notNull()
                t.column("localPath", .text)
                t.column("totalBytes", .integer)
                t.column("receivedBytes", .integer).notNull().defaults(to: 0)
                t.column("errorMessage", .text)
                t.column("requestedAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }
            try db.create(index: "download_state", on: "download", columns: ["state"])
        }

        migrator.registerMigration("v5_extra_type") { db in
            // Extras — trailers, featurettes, behind-the-scenes — are ordinary
            // Episode or Video rows with an ExtraType set. Without the column there
            // is no way to tell one from real content, so they cannot be kept out of
            // the library or gathered under a title where they belong.
            try db.alter(table: "item") { t in
                t.add(column: "extraType", .text)
            }
            try db.create(index: "item_extra_type", on: "item", columns: ["extraType"])
        }

        migrator.registerMigration("v6_library_id") { db in
            // The owning library, separate from parentId.
            //
            // Stamping the library onto parentId made every grid work and silently
            // broke series detail: `seasons(seriesId:)` finds seasons by
            // parentId == seriesId, and that link no longer existed. parentId is
            // Jellyfin's immediate parent and has to stay that.
            try db.alter(table: "item") { t in
                t.add(column: "libraryId", .text)
            }
            try db.create(index: "item_library", on: "item", columns: ["libraryId", "sortName"])
        }

        migrator.registerMigration("v7_hidden_shelf_items") { db in
            // Items dismissed from Continue Watching and Next Up.
            //
            // A table rather than UserDefaults: this is a decision about specific
            // library items, it has to survive a relaunch, and it belongs with the
            // rows it refers to. Deliberately NOT sent to the server — Jellyfin has
            // no concept of "hide from my shelves", and marking something watched to
            // fake it would corrupt real watch history.
            try db.create(table: "hiddenShelfItem") { t in
                t.primaryKey("itemId", .text)
                t.column("hiddenAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v8_track_preference") { db in
            // Remembered audio and subtitle choices, keyed by series — or by the item
            // itself for a film.
            //
            // Languages, not track indices. An index is meaningful only within one
            // file: episode 1 might carry Japanese as track 2 and episode 2 as track
            // 1, and a remembered index would silently switch you to the dub. Language
            // is the thing the user actually chose.
            try db.create(table: "trackPreference") { t in
                t.primaryKey("key", .text)
                t.column("audioLanguage", .text)
                t.column("subtitleLanguage", .text)
                t.column("subtitlesEnabled", .boolean).notNull().defaults(to: true)
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v9_collection_shelf_label") { db in
            // Which shelf a collection member sits under, when the automatic
            // grouping by source library isn't the one wanted — a crossover title
            // filed under a shelf that doesn't match any library it lives in.
            //
            // Local only, like hiddenShelfItem: Jellyfin has no concept of a
            // sub-grouping inside a BoxSet, so this cannot be synced and does not
            // try to be. It is keyed by the pair, not just itemId, because the same
            // title can sit in more than one collection with a different label in
            // each.
            try db.create(table: "collectionShelfLabel") { t in
                t.column("collectionId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("label", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["collectionId", "itemId"])
            }
        }

        Self.registerLaterMigrations(&migrator)

        return migrator


    }
}
