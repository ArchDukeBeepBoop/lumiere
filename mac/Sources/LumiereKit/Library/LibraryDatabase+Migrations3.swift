import Foundation
import GRDB

/// The most recent migrations.
///
/// Split from LibraryDatabase+Migrations2.swift for the project's 300-line rule.
/// Append-only, like every migration file here: a numbered migration that has run
/// anywhere is never edited, only followed.
extension LibraryDatabase {

    static func registerRecentMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v18_content_date") { db in
            // When the newest *thing you can watch* under this row arrived.
            //
            // For everything but a series it is the row's own creation date. For a
            // series it is the date of its newest episode, and that difference is
            // the whole point: Jellyfin stamps a Series row with when its *folder*
            // was scanned, so a library rescan makes every show look new at once
            // while the episodes inside them are years old. On this library that put
            // six shows last touched in 2019 at the head of Latest Anime and left
            // them there, because a rescan is not something that happens again soon.
            //
            // Stored rather than computed. The obvious query — order by a correlated
            // `max(episode.dateCreated)` — has to run the subquery for every
            // candidate row before it can sort, and measured over 45,000 rows it did
            // not finish in five minutes. As a column it is an indexed sort, and the
            // subquery runs once per series at the end of that library's sync.
            try db.alter(table: "item") { t in
                t.add(column: "contentDate", .datetime)
            }
            // Everything starts as its own date, so nothing sorts as NULL before the
            // first sync has a chance to refine the series rows.
            try db.execute(sql: "UPDATE item SET contentDate = dateCreated")

            // Created *here*, before the correlated UPDATE below, and not only in
            // v19 where it also lives. Migrations run in registration order, so on
            // any database that has rows before it has this migration — restoring a
            // backup is the obvious way, and this session produced one — v18 would
            // run that UPDATE unindexed. Measured on a 45,000-row cache that is
            // **56 seconds**, synchronous, holding the write lock, before the window
            // appears. With the index it is 0.06s.
            //
            // Editing an already-applied migration would normally be forbidden here,
            // and this is the one shape where it is safe: GRDB records identifiers,
            // never bodies, so a database that has run v18 will not run it again and
            // cannot be affected. v19 keeps its own copy for exactly that case —
            // both are `ifNotExists`, so whichever arrives second does nothing.
            try db.create(
                index: "item_on_series_episode", on: "item",
                columns: ["seriesId", "type", "dateCreated"], ifNotExists: true
            )
            try db.execute(sql: """
                UPDATE item SET contentDate = COALESCE(
                    (SELECT max(e.dateCreated) FROM item e
                      WHERE e.seriesId = item.id AND e.type = 'Episode'),
                    dateCreated
                )
                WHERE type = 'Series'
                """)
            try db.create(
                index: "item_on_content_date", on: "item", columns: ["contentDate"]
            )
        }


        migrator.registerMigration("v19_series_episode_index") { db in
            // The index that makes `refreshContentDates` survivable.
            //
            // Without it that UPDATE took **56 seconds** on this library, and it runs
            // at the end of every library sync while holding SQLite's write lock —
            // so the app froze, reads and all, for a minute at a time. It was not
            // subtle: the sync log simply stopped after "incremental stopped" and
            // nothing else happened for minutes.
            //
            // The cause was index choice, not row count. The subquery filters on
            // `seriesId` and `type`, and the planner preferred `item_on_type_created`
            // — so for each of 737 series it scanned all 36,610 episodes. Offering a
            // composite in the subquery's own shape makes it a covering index and the
            // whole thing a range lookup: 56.5s to 0.09s, and 0.06s for every library
            // at once. The index itself builds in 0.2s.
            //
            // `dateCreated` is the third column so `max()` is answered from the index
            // order rather than by reading the rows.
            try db.create(
                index: "item_on_series_episode", on: "item",
                columns: ["seriesId", "type", "dateCreated"], ifNotExists: true
            )
        }


        migrator.registerMigration("v20_last_played") { db in
            // When the server says something was last watched.
            //
            // Continue Watching was ordered by `item.dateCreated` — when the *file*
            // was imported — so the shelf was sorted by library age rather than by
            // what you were doing. On this library that put a title watched minutes
            // ago outside the first fourteen rows, behind files added months
            // earlier, and with the shelf capped at twelve it simply was not there.
            //
            // `updatedAt` is not a substitute: the sync stamps it on every row it
            // refreshes, so it reads as "when we last talked to the server" for most
            // items. This is Jellyfin's own `LastPlayedDate`, which it has been
            // sending all along and this app was throwing away.
            //
            // Backfilled to NULL rather than to `updatedAt`, which would invent a
            // history that is not there. The next sync fills it in.
            try db.alter(table: "userData") { t in
                t.add(column: "lastPlayedDate", .datetime)
            }
            try db.create(
                index: "userdata_on_last_played", on: "userData",
                columns: ["lastPlayedDate"], ifNotExists: true
            )
        }

        migrator.registerMigration("v21_playback_outbox") { db in
            // Watch progress made while the server was away, waiting to be told.
            //
            // Playing offline already worked and already recorded a position — but
            // only in this cache. The report to the server was a `try?` that failed
            // silently, so an evening watched on a train was an evening no other
            // Jellyfin client, and no later sync, would ever know about. Worse, the
            // next sync overwrote the local position with the server's stale one, so
            // the progress was not merely unshared, it was destroyed.
            //
            // A row per item rather than per report: only the newest position for a
            // title is worth sending, and `positionTicks` is simply overwritten as
            // playback continues. The queue therefore stays the size of the number of
            // things watched offline, not the number of ten-second ticks.
            try db.create(table: "playbackOutbox") { t in
                t.column("itemId", .text).primaryKey()
                t.column("positionTicks", .integer).notNull()
                t.column("played", .boolean).notNull().defaults(to: false)
                // What the position is *of*. Jellyfin's progress endpoint wants it,
                // and it is not derivable later from the cache alone.
                t.column("mediaSourceId", .text)
                t.column("recordedAt", .datetime).notNull()
            }
            try db.create(
                index: "outbox_on_recorded", on: "playbackOutbox",
                columns: ["recordedAt"], ifNotExists: true
            )
        }

        migrator.registerMigration("v22_item_path_index") { db in
            // The folder browser keys on the path now, not on Jellyfin's ParentId,
            // because the two disagree: on the `3D` library fifteen rows had a parent
            // whose own path was not their containing directory, and one folder the
            // files clearly live in was not cached at all. A prefix range over `path`
            // is how children are found, and without an index that is a full scan of
            // 45,000 rows for every folder opened.
            try db.create(
                index: "item_on_path", on: "item", columns: ["path"], ifNotExists: true
            )
        }

        migrator.registerMigration("v23_item_version") { db in
            // The other files Jellyfin folded into one item.
            //
            // Several video files in a single folder become one Movie with the rest
            // hanging off it as extra MediaSources, so a folder listing built from
            // items showed one tile where the user had put ten files. Measured on
            // `3D`: each `Clips/Compilations/…` folder returned exactly one item,
            // while `Clips/Lantern Road` returned seven — Lantern Road's filenames were
            // different enough that the server did not merge them.
            //
            // Stored rather than fetched on demand so a folder still lists correctly
            // with the server away, which is the whole point of the cache.
            try db.create(table: "itemVersion") { t in
                t.column("itemId", .text).notNull()
                    .references("item", onDelete: .cascade)
                t.column("sourceId", .text).notNull()
                t.column("path", .text)
                t.column("name", .text)
                t.primaryKey(["itemId", "sourceId"])
            }
            try db.create(
                index: "itemversion_on_item", on: "itemVersion",
                columns: ["itemId"], ifNotExists: true
            )
        }

        migrator.registerMigration("v24_item_studios") { db in
            // Who made it. Cached for the same reason genres are: the studio picker
            // is built from what this library actually holds, and asking the server
            // for that list on every visit would be a round trip to draw a menu.
            //
            // Newline-joined, like `genres`, because that is the separator the
            // existing list column already uses and a studio name can contain a
            // comma but not a newline.
            try db.alter(table: "item") { t in
                t.add(column: "studios", .text)
            }
        }

        migrator.registerMigration("v25_library_primary_tag") { db in
            // The library's own poster, as set in Jellyfin.
            //
            // The home screen used to draw a library card from the newest title
            // inside it, which meant the picture for "Anime" changed every time
            // anything was added — a navigation tile that does not stay the same
            // is one nobody can learn. Jellyfin already holds a poster per
            // library; this is the tag that fetches it.
            try db.alter(table: "library") { t in
                t.add(column: "primaryTag", .text)
            }
        }

        migrator.registerMigration("v26_intro_skip") { db in
            // Where a series' intro is, learned from where the viewer skips.
            //
            // Local rather than on the server, and that is deliberate: it is a
            // record of this person's behaviour, it is derived rather than
            // authoritative, and a server that later grows real segments should
            // win over it without anything having to be reconciled.
            try db.create(table: "introSkip") { t in
                t.primaryKey("seriesId", .text)
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("samples", .integer).notNull().defaults(to: 1)
                t.column("updatedAt", .datetime).notNull()
            }
        }
        registerNewestMigrations(&migrator)
    }
}
