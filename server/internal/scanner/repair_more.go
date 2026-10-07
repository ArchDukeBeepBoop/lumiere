package scanner

import (
	"database/sql"
	"log/slog"
	"os"
	"time"
)

// Split from repair.go for the 300-line rule.

func restoreAddedDates(db *sql.DB, log *slog.Logger) error {
	// Every row the scanner wrote, found by shape rather than by the hour a
	// particular run happened to fall in: the first repair matched one ten-
	// minute window and left the containers written either side of it, so seven
	// decade-old shows stayed at the top of Recently Added.
	//
	// A container has no path of its own to ask, so its folder is used — which
	// for a series is the path the scanner stored on it.
	rows, err := db.Query(`
		SELECT id, path FROM item
		WHERE path IS NOT NULL AND path <> ''
		  AND date_created > ? AND date_created < ?`,
		scanEpoch, time.Now().UTC().Format(time.RFC3339))
	if err != nil {
		return err
	}
	type fix struct{ id, when string }
	var fixes []fix
	for rows.Next() {
		var id, path string
		if err := rows.Scan(&id, &path); err != nil {
			rows.Close()
			return err
		}
		info, err := os.Stat(path)
		if err != nil {
			// The file is gone; its date is the least of that row's problems.
			continue
		}
		fixes = append(fixes, fix{id, info.ModTime().UTC().Format(time.RFC3339)})
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	// Containers the scanner wrote before it stored their folder have no path
	// to ask, so they were skipped and kept the scan's clock — seven decade-old
	// shows sitting at the top of Recently Added. A show arrived when its first
	// episode did, which is both derivable and true.
	// Children found by whichever link they carry. A "Season Unknown" holds
	// episodes that name it as their season while naming a *different* row as
	// their series, so joining on series_id alone left those seasons stamped
	// with the scan's clock — and a season dated today puts its show back at
	// the top of Recently Added.
	containers, err := db.Query(`
		SELECT parent.id, MIN(child.date_created)
		FROM item parent
		JOIN item child
		  ON child.series_id = parent.id
		  OR child.season_id = parent.id
		  OR child.parent_id = parent.id
		WHERE parent.type IN ('Series', 'Season')
		  AND (parent.path IS NULL OR parent.path = '')
		  AND parent.date_created > ?
		  AND child.date_created IS NOT NULL
		GROUP BY parent.id`, scanEpoch)
	if err != nil {
		return err
	}
	for containers.Next() {
		var id, when string
		if err := containers.Scan(&id, &when); err != nil {
			containers.Close()
			return err
		}
		fixes = append(fixes, fix{id, when})
	}
	containers.Close()
	if err := containers.Err(); err != nil {
		return err
	}

	if len(fixes) == 0 {
		return nil
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, f := range fixes {
		if _, err := tx.Exec(
			`UPDATE item SET date_created = ? WHERE id = ?`, f.when, f.id); err != nil {
			return err
		}
	}
	log.Info("repair: restored added dates", "rows", len(fixes))
	return tx.Commit()
}

// dropPhantomSeries removes a show the scanner invented for a film.
//
// An `EXTRA` folder beside four films read as a season, so a series was built
// for a folder whose contents were already catalogued as movies — and it then
// sat in Recently Added with no artwork, which is how it was noticed.
//
// Narrow on purpose. Only in a library Jellyfin calls `movies`, only with no
// artwork of its own, and only where every child it has is already marked as a
// supplement — a series with a real episode under it is a real series, whatever
// library it landed in.
func dropPhantomSeries(db *sql.DB, log *slog.Logger) error {
	rows, err := db.Query(`
		SELECT s.id, s.name FROM item s
		WHERE s.type = 'Series'
		  AND NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = s.id)
		  AND EXISTS (
			SELECT 1 FROM library_folder lf
			JOIN item v ON v.id = lf.view_id
			WHERE lf.folder_id = s.library_id AND v.collection_type = 'movies'
		  )
		  AND NOT EXISTS (
			SELECT 1 FROM item child
			WHERE child.series_id = s.id AND child.type = 'Episode'
			  AND child.extra_type IS NULL
		  )`)
	if err != nil {
		return err
	}
	type phantom struct{ id, name string }
	var phantoms []phantom
	for rows.Next() {
		var p phantom
		if err := rows.Scan(&p.id, &p.name); err != nil {
			rows.Close()
			return err
		}
		phantoms = append(phantoms, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, p := range phantoms {
		tx, err := db.Begin()
		if err != nil {
			return err
		}
		// The supplements stay — they are real files and correctly marked. Only
		// their invented parentage goes, so they hang off the folder they are
		// actually in rather than a show that does not exist.
		if _, err := tx.Exec(
			`UPDATE item SET series_id = NULL WHERE series_id = ?`, p.id); err != nil {
			tx.Rollback()
			return err
		}
		if _, err := tx.Exec(
			`DELETE FROM item WHERE type = 'Season' AND parent_id = ?`, p.id); err != nil {
			tx.Rollback()
			return err
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, p.id); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		log.Info("repair: dropped a series invented for a film", "name", p.name)
	}
	return nil
}
