package scanner

import (
	"database/sql"
	"log/slog"
	"lumiere-server/internal/store"
)

// Repair undoes the three mistakes the first scan made.
//
// It ran before the rules below existed, so the rows it wrote carry them: shows
// duplicated because they were matched by name, supplements filed as episodes,
// and every one of them stamped with the scan's own clock. All three are
// visible in the app rather than theoretical — a Latest shelf full of creditless
// openings, and a Dr Stone with no artwork beside the real Dr. STONE.
//
// Idempotent and safe to run at every startup: each step only touches rows that
// still have the problem.
// Repair returns how many rows it changed into something new — a film that
// became an episode of a show that did not exist a moment ago — so the caller
// can send the metadata pass after them even on a scan that added no files.
func Repair(db *sql.DB, log *slog.Logger) (int, error) {
	if err := mergeDuplicateSeries(db, log); err != nil {
		return 0, err
	}
	if err := reclassifyExtras(db, log); err != nil {
		return 0, err
	}
	// After extras, so a creditless opening is not counted as a sibling; before
	// the phantom sweep, so the shows this makes are not swept as empty.
	folded, err := foldEpisodeFilms(db, log)
	if err != nil {
		return 0, err
	}
	// After reclassifyExtras, which it partly reverses — see restoreSpecials.
	if restored, err := restoreSpecials(db, log); err != nil {
		return 0, err
	} else {
		folded += restored
	}
	if err := dropPhantomSeries(db, log); err != nil {
		return 0, err
	}
	// Every episode in a season, so every episode is listed. See seat.go.
	if seated, err := seatLooseEpisodes(db, log); err != nil {
		return 0, err
	} else {
		folded += seated
	}
	// Then put back any the seating once put in the wrong season. See reseat.go.
	if moved, err := reseatBySeasonNumber(db, log); err != nil {
		return 0, err
	} else {
		folded += moved
	}
	// What a move or a removal leaves behind: a season with no episodes, a
	// series with no seasons. Only the scanner's own — see dropEmptyContainers.
	if healed, err := healSeasonLinks(db); err != nil {
		return 0, err
	} else if healed > 0 {
		log.Info("repair: healed season links", "episodes", healed)
	}
	// Two rows for one file — the import's twin of a file the scanner found
	// first. Folded into the scanner's row. See store.MergeTwins.
	if merged, err := (&store.Store{DB: db}).MergeTwins(); err != nil {
		return 0, err
	} else if merged > 0 {
		log.Info("repair: merged duplicate rows for one file", "count", merged)
		folded += merged
	}
	if merged, err := (&store.Store{DB: db}).MergeEmptySeries(); err != nil {
		return 0, err
	} else if merged > 0 {
		log.Info("repair: merged hollow shows into their full twins", "count", merged)
		folded += merged
	}
	if cleared, err := unblockEpisodeNames(db, log); err != nil {
		return 0, err
	} else {
		folded += cleared
	}
	if dropped, err := (&store.Store{DB: db}).DropEmptySeries(); err != nil {
		return 0, err
	} else if dropped > 0 {
		log.Info("repair: dropped shows with no episodes", "count", dropped)
		folded += dropped
	}
	if dropped, err := dropEmptyContainers(db); err != nil {
		return 0, err
	} else if dropped > 0 {
		log.Info("repair: dropped empty containers", "count", dropped)
	}
	// Pictures whose files are gone, so something refills them. See goneimages.go.
	if dropped, err := dropGoneImages(db, log); err != nil {
		return 0, err
	} else {
		folded += dropped
	}
	// Collections made outside the Collections library. See store.collectionsHome.
	if homed, err := (&store.Store{DB: db}).HomeStrayCollections(); err != nil {
		return 0, err
	} else if homed > 0 {
		log.Info("repair: filed stray collections into the Collections library", "count", homed)
		folded += homed
	}
	return folded, restoreAddedDates(db, log)
}

// mergeDuplicateSeries folds a scanner-made show into the one it belongs to.
//
// Matched on the folder, which is the identity the scanner should have used in
// the first place: two series rows whose episodes live under the same directory
// are one show. The posterless copy loses.
func mergeDuplicateSeries(db *sql.DB, log *slog.Logger) error {
	rows, err := db.Query(`
		SELECT dupe.id, keep.id, keep.name
		FROM item dupe
		JOIN item keep ON keep.type = 'Series' AND keep.id <> dupe.id
		WHERE dupe.type = 'Series'
		  -- The duplicate is the one with no artwork; the imported row has it.
		  AND NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = dupe.id)
		  AND EXISTS (SELECT 1 FROM image g WHERE g.item_id = keep.id)
		  -- Same show: their episodes sit under one directory.
		  AND EXISTS (
			SELECT 1 FROM item a JOIN item b
			  ON substr(a.path, 1, length(keep.path)) = keep.path
			WHERE a.series_id = dupe.id AND b.id = keep.id
			  AND keep.path IS NOT NULL AND keep.path <> ''
		  )`)
	if err != nil {
		return err
	}
	defer rows.Close()

	type merge struct{ from, to, name string }
	var merges []merge
	for rows.Next() {
		var m merge
		if err := rows.Scan(&m.from, &m.to, &m.name); err != nil {
			return err
		}
		merges = append(merges, m)
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for _, m := range merges {
		tx, err := db.Begin()
		if err != nil {
			return err
		}
		// The episodes move first, then the seasons, then the empty shell goes.
		if _, err := tx.Exec(
			`UPDATE item SET series_id = ? WHERE series_id = ?`, m.to, m.from); err != nil {
			tx.Rollback()
			return err
		}
		if _, err := tx.Exec(
			`UPDATE item SET parent_id = ? WHERE parent_id = ? AND type = 'Season'`,
			m.to, m.from); err != nil {
			tx.Rollback()
			return err
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, m.from); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		log.Info("repair: merged duplicate series", "into", m.name)
	}
	return nil
}

// reclassifyExtras marks the supplements the first scan filed as episodes.
//
// Only rows the scanner wrote — the ones with no extra type and a path — and
// only where the rules now say supplement. Jellyfin's own classifications are
// never revisited.
func reclassifyExtras(db *sql.DB, log *slog.Logger) error {
	rows, err := db.Query(`
		SELECT i.id, i.path, COALESCE(f.path, '')
		FROM item i
		LEFT JOIN library_folder lf ON lf.folder_id = i.library_id
		LEFT JOIN item f ON f.id = i.library_id
		WHERE i.extra_type IS NULL AND i.path IS NOT NULL
		  AND i.type IN ('Episode', 'Video', 'Movie')`)
	if err != nil {
		return err
	}
	type change struct{ id, kind string }
	var changes []change
	for rows.Next() {
		var id, path, root string
		if err := rows.Scan(&id, &path, &root); err != nil {
			rows.Close()
			return err
		}
		if root == "" {
			continue
		}
		if kind := ExtraType(root, path); kind != "" {
			changes = append(changes, change{id, kind})
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	if len(changes) == 0 {
		return nil
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, c := range changes {
		if _, err := tx.Exec(
			`UPDATE item SET extra_type = ? WHERE id = ? AND extra_type IS NULL`,
			c.kind, c.id); err != nil {
			return err
		}
	}
	log.Info("repair: reclassified supplements", "rows", len(changes))
	return tx.Commit()
}

// restoreAddedDates puts back the timestamp the file actually has.
//
// The scan stamped its own clock on everything it added, which put a decade of
// never-catalogued extras at the top of every Latest shelf. Only rows whose
// date is inside the window that scan ran in are touched, so nothing Jellyfin
// dated is disturbed.
// scanEpoch is the moment the scanner first ran here. Nothing legitimately
// dated after it came from Jellyfin, so anything later with a path on disk is a
// row this scanner wrote and can be re-dated from the file.
const scanEpoch = "2026-09-09T02:00:00Z"
