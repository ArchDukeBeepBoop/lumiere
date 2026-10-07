import Foundation
import GRDB

/// The migrations that repair an existing cache rather than shape a new one.
///
/// Split from LibraryDatabase+Migrations.swift for the project's 300-line limit.
/// Both of these exist because the app learned something the cache did not know —
/// which folders hold bonus material, and how a title should be searched — and
/// back-filling is minutes of local work against minutes of network for a
/// 44,000-item library.
extension LibraryDatabase {
    static func registerLaterMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10_backfill_extras_from_path") { db in
            // Back-fills what ItemRecord now classifies on the way in, so an existing
            // cache is fixed without a full re-sync — which on a 44,000-item library
            // is minutes of work to learn something already on disk.
            //
            // The SQL mirrors ExtrasClassifier's folder list. Kept as LIKE patterns on
            // the directory portion rather than calling into Swift, because a
            // migration runs inside the GRDB write block and cannot reach the
            // classifier's Foundation path splitting. `%/name/%` anchors each match to
            // a whole directory component, so a film called "Trailer Park Boys" is not
            // caught by its own filename.
            let folders = [
                "extras", "extra", "bonus", "bonus disc", "bonusdisc",
                "featurettes", "featurette",
                "behind the scenes", "behindthescenes",
                "deleted scenes", "deletedscenes",
                "interviews", "interview",
                "trailers", "trailer",
                "samples", "sample",
                "special features", "specialfeatures",
                "making of", "makingof",
            ]
            let clause = folders
                .map { _ in "LOWER(path) LIKE ?" }
                .joined(separator: " OR ")
            let arguments = folders.map { "%/\($0)/%" }

            // Episodes excluded, matching the classifier: anime specials and OVAs sit
            // in `Specials/` and are real content, and reclassifying them would have
            // hidden 519 episodes from their own season lists.
            try db.execute(
                sql: "UPDATE item SET extraType = 'Extra' "
                   + "WHERE extraType IS NULL AND path IS NOT NULL "
                   + "AND type <> 'Episode' AND (\(clause))",
                arguments: StatementArguments(arguments)
            )
        }

        migrator.registerMigration("v11_search_key") { db in
            // A searchable form of each row, because the old query could not find
            // things that were plainly there. `LIKE '%term%'` on `name` alone means
            // three separate failures: "fate zero" misses Fate/Zero because the
            // slash is not a space, "academy sky" misses Sky Wizards Academy because
            // a substring has to be contiguous and in order, and an episode could
            // not be found by the show it belongs to at all.
            //
            // Back-filled here rather than waiting for a re-sync: on a 44,000-item
            // library that is minutes of network to recompute something already on
            // disk. The SQL mirrors SearchKey.normalize — lowercase, and every
            // punctuation mark that actually occurs in these titles turned into a
            // space rather than removed, so "Fate/Zero" becomes two words instead
            // of one run-together one.
            try db.alter(table: "item") { table in
                table.add(column: "searchKey", .text).notNull().defaults(to: "")
            }

            // Chunked into several statements rather than one expression.
            // Nesting twenty-nine `replace()` calls overflows SQLite's parser stack
            // outright — the migration threw rather than producing a wrong answer,
            // which is the good version of that mistake but still a failed upgrade.
            let punctuation = ["/", "\\", ":", "-", "_", ".", ",", "'", "\"", "!",
                               "?", "(", ")", "[", "]", "{", "}", "&", "+", "*",
                               "~", "|", ";", "#", "@", "%", "=", "<", ">"]

            try db.execute(
                sql: "UPDATE item SET searchKey = lower(name || ' ' || coalesce(seriesName, ''))"
            )
            for chunk in stride(from: 0, to: punctuation.count, by: 5) {
                let marks = Array(punctuation[chunk..<min(chunk + 5, punctuation.count)])
                var expression = "searchKey"
                for _ in marks {
                    // Bound, not interpolated: an apostrophe is one of the marks
                    // being replaced, and inlining it closes the SQL string literal
                    // it is sitting inside. The statement failed loudly, which is
                    // the good version of that mistake — but it is exactly the shape
                    // of an injection bug, and binding removes the class entirely.
                    expression = "replace(\(expression), ?, ' ')"
                }
                try db.execute(
                    sql: "UPDATE item SET searchKey = \(expression)",
                    arguments: StatementArguments(marks)
                )
            }

            // Indexed because every keystroke in the search field runs against it.
            try db.create(index: "item_search", on: "item", columns: ["searchKey"])
        }

        migrator.registerMigration("v12_original_title") { db in
            // The alternative name a show is often better known by. Anime is the
            // case that forces it: half a library goes by a romaji or Japanese
            // title that appears nowhere in the display name, so searching for
            // the name someone actually knows found nothing at all.
            //
            // Left empty here rather than back-filled. Unlike the search key,
            // this is not derivable from anything already on disk — the value has
            // to come from the server, so it arrives with the next full scan.
            try db.alter(table: "item") { table in
                table.add(column: "originalTitle", .text)
            }
        }

        migrator.registerMigration("v13_collection_rank") { db in
            // Where a title sits in a collection when you have said so yourself.
            //
            // Local, like the shelf labels beside it, and for the same reason: a
            // BoxSet's server-side order is a single global arrangement, and this is
            // a personal viewing order — the sequence someone recommends watching a
            // franchise in, which is neither release order nor the order the
            // collection was built in. Two people sharing a server should not fight
            // over it.
            //
            // Ranks are sparse on purpose. Inserting between two neighbours must not
            // rewrite every row after it, so they are spaced and only renumbered
            // when a gap closes.
            try db.create(table: "collectionRank") { t in
                t.column("collectionId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("rank", .integer).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["collectionId", "itemId"])
            }
            try db.create(
                index: "collectionRank_order", on: "collectionRank",
                columns: ["collectionId", "rank"]
            )
        }

        migrator.registerMigration("v14_hidden_collection") { db in
            // Collections Lumiere should not show, even though the server still has
            // them.
            //
            // Jellyfin's TMDB scraper creates a BoxSet for every film that belongs to
            // a TMDB collection — "Ant-Man Collection", "A Quiet Place Collection" —
            // and re-creates them on the next library scan. Deleting one therefore
            // works and then undoes itself, which is why they kept coming back: the
            // delete was never the broken part. Turning the server setting off is the
            // only way to stop them being made; this is how you get rid of the ones
            // it has already made without waiting for that.
            //
            // Local by necessity: the server has no notion of an item a client
            // declines to display.
            try db.create(table: "hiddenCollection") { t in
                t.primaryKey("itemId", .text)
                t.column("name", .text).notNull()
                t.column("hiddenAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v15_track_credits") { db in
            // What a track list has to say beyond the song's name.
            //
            // No backfill, and none is needed: music is never synced — every screen
            // of it is a live request, see LibraryRepository+MusicPaging — so these
            // fill in on the next page anybody reads, which is the next time anybody
            // looks at a track.
            try db.alter(table: "item") { t in
                t.add(column: "album", .text)
                t.add(column: "albumArtist", .text)
                t.add(column: "artists", .text)
            }
        }

        migrator.registerMigration("v16_subtitle_offset") { db in
            // How far this one file's subtitles are out.
            //
            // Per item, not per app. The first version of this saved a single
            // number in UserDefaults and applied it to everything, on the theory
            // that a lag is a property of a setup — it is not. A subtitle track cut
            // for a different release is out by an amount that belongs to that
            // file, and carrying it to the next episode breaks a track that was
            // fine.
            //
            // Its own table rather than a column on `item`, because it is a local
            // decision about a file and nothing the server sends: a row here must
            // survive a sync that rewrites everything the server does own.
            try db.create(table: "subtitleOffset") { t in
                t.primaryKey("itemId", .text)
                t.column("seconds", .double).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v17_hidden_collection_name") { db in
            // Hiding by name as well as by id.
            //
            // Keying on the id alone did not work, and could not have. Jellyfin's
            // TMDB scraper does not resurrect the BoxSet you deleted — it creates a
            // *new* one, with a new id, on the next library scan. So a tombstone
            // holding the old id matches nothing, and the collection is back under
            // a different primary key with the same name on the shelf.
            //
            // The name is what a person means by "that collection", so that is what
            // is remembered. Matched only against BoxSets, so a film that happens to
            // share a collection's name is not hidden with it.
            try db.alter(table: "hiddenCollection") { t in
                t.add(column: "nameKey", .text)
            }
            try db.execute(sql: "UPDATE hiddenCollection SET nameKey = lower(trim(name))")
        }

        registerRecentMigrations(&migrator)
    }
}
