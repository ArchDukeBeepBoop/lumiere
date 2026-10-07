package store

import (
	"database/sql"
	"fmt"
	"strings"
)

// Twins: two rows for one file.
//
// The scanner keys a file by its path, and Jellyfin keyed the same file by a
// GUID of its own; an import run after the scanner had already found a file
// wrote a second row for it, and every list showed the episode twice. The
// importer now skips a path the scanner holds. This mends the ones already
// written, without losing what either row knew: the row written first is
// kept — the scanner's, whose id the client's cache and watch state carry —
// and whatever the twin had that it lacks is moved across before the twin
// goes.

// twinTables are the tables keyed by item id, with the columns after item_id
// that complete each key, so a row moves only where the kept id has none.
var twinTables = []struct{ table, keyCols string }{
	{"user_data", ""},
	{"image", "kind, idx"},
	{"stream", "idx"},
	{"item_value", "kind, value"},
	{"person", "person_id, type, role"},
	{"chapter", "idx"},
	{"segment", "type, start_ticks"},
	{"mkv_segment", ""},
	{"mkv_link", "position"},
}

// MergeTwins folds every duplicate-path row into the one written first.
// Returns how many rows were folded away.
func (s *Store) MergeTwins() (int, error) {
	rows, err := s.DB.Query(`
		SELECT path FROM item
		WHERE path IS NOT NULL AND path <> '' AND is_folder = 0
		GROUP BY path HAVING count(*) > 1`)
	if err != nil {
		return 0, err
	}
	var paths []string
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			rows.Close()
			return 0, err
		}
		paths = append(paths, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	merged := 0
	for _, path := range paths {
		n, err := s.mergeTwinsAt(path)
		if err != nil {
			return merged, fmt.Errorf("merge %s: %w", path, err)
		}
		merged += n
	}
	return merged, nil
}

func (s *Store) mergeTwinsAt(path string) (int, error) {
	tx, err := s.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	// First written first: rowid is insertion order, and the scanner's row
	// precedes the import's — the scanner never adds a path it already holds.
	idRows, err := tx.Query(`SELECT id, name FROM item WHERE path = ? ORDER BY rowid`, path)
	if err != nil {
		return 0, err
	}
	var ids, names []string
	for idRows.Next() {
		var id, name string
		if err := idRows.Scan(&id, &name); err != nil {
			idRows.Close()
			return 0, err
		}
		ids, names = append(ids, id), append(names, name)
	}
	idRows.Close()
	if len(ids) < 2 {
		return 0, nil
	}
	keep := ids[0]

	for i, twin := range ids[1:] {
		if err := moveChildRows(tx, twin, keep); err != nil {
			return 0, err
		}
		// The twin's naming, where the kept row still wears its filename.
		if looksUnnamed(names[0]) && !looksUnnamed(names[i+1]) {
			if _, err := tx.Exec(`
				UPDATE item SET name = t.name, sort_name = t.sort_name, overview = t.overview,
				    premiere_date = COALESCE(item.premiere_date, t.premiere_date),
				    community_rating = COALESCE(item.community_rating, t.community_rating)
				FROM (SELECT name, sort_name, overview, premiere_date, community_rating
				      FROM item WHERE id = ?) AS t
				WHERE item.id = ?`, twin, keep); err != nil {
				return 0, err
			}
		}
		if _, err := tx.Exec(`UPDATE item SET parent_id = ? WHERE parent_id = ?`, keep, twin); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, twin); err != nil {
			return 0, err
		}
	}
	return len(ids) - 1, tx.Commit()
}

// moveChildRows carries every keyed row from one item to another where the
// receiver lacks it; what the receiver already has, the giver's copy is a
// duplicate and goes. Nothing keyed by the giver survives.
func moveChildRows(tx *sql.Tx, from, to string) error {
	for _, t := range twinTables {
		absent := "NOT EXISTS (SELECT 1 FROM " + t.table + " k WHERE k.item_id = ?"
		for _, c := range strings.Split(t.keyCols, ", ") {
			if c != "" {
				absent += " AND k." + c + " = " + t.table + "." + c
			}
		}
		absent += ")"
		if _, err := tx.Exec(
			"UPDATE "+t.table+" SET item_id = ? WHERE item_id = ? AND "+absent, to, from, to,
		); err != nil {
			return err
		}
		if _, err := tx.Exec("DELETE FROM "+t.table+" WHERE item_id = ?", from); err != nil {
			return err
		}
	}
	return nil
}

// MergeEmptySeries folds a show with no episodes into the show of the same
// name in the same library that has them.
//
// The other half of an import after a scan: the file rows were twins, and
// merging them left Jellyfin's series and seasons standing with nothing
// under them — the home screen showed every new show twice, one of them
// hollow. The hollow one's artwork and watch state move to the full one
// where it lacks them; its seasons go with it.
func (s *Store) MergeEmptySeries() (int, error) {
	rows, err := s.DB.Query(`
		SELECT hollow.id, whole.id FROM item hollow
		JOIN item whole ON whole.type = 'Series' AND whole.id <> hollow.id
		  AND whole.name = hollow.name
		  AND COALESCE(whole.library_id, '') = COALESCE(hollow.library_id, '')
		WHERE hollow.type = 'Series'
		  AND NOT EXISTS (SELECT 1 FROM item e WHERE e.series_id = hollow.id AND e.type = 'Episode')
		  AND EXISTS (SELECT 1 FROM item e WHERE e.series_id = whole.id AND e.type = 'Episode')`)
	if err != nil {
		return 0, err
	}
	type pair struct{ hollow, full string }
	var pairs []pair
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.hollow, &p.full); err != nil {
			rows.Close()
			return 0, err
		}
		pairs = append(pairs, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	merged := 0
	for _, p := range pairs {
		tx, err := s.DB.Begin()
		if err != nil {
			return merged, err
		}
		if err := moveChildRows(tx, p.hollow, p.full); err != nil {
			tx.Rollback()
			return merged, err
		}
		if err := dropSeriesShell(tx, p.hollow); err != nil {
			tx.Rollback()
			return merged, err
		}
		if err := tx.Commit(); err != nil {
			return merged, err
		}
		merged++
	}
	return merged, nil
}

// DropEmptySeries removes every show with no episodes at all.
//
// After MergeEmptySeries has folded the ones with a full twin, what is left
// is a show nothing points at: a folder renamed under it, files the scanner
// filed under another title, an import row for a show that was moved away.
// The home screen drew each as a series with a poster and nothing inside.
func (s *Store) DropEmptySeries() (int, error) {
	rows, err := s.DB.Query(`
		SELECT id FROM item s WHERE type = 'Series'
		  AND NOT EXISTS (SELECT 1 FROM item e WHERE e.series_id = s.id AND e.type = 'Episode')`)
	if err != nil {
		return 0, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	dropped := 0
	for _, id := range ids {
		tx, err := s.DB.Begin()
		if err != nil {
			return dropped, err
		}
		if err := dropSeriesShell(tx, id); err != nil {
			tx.Rollback()
			return dropped, err
		}
		if err := tx.Commit(); err != nil {
			return dropped, err
		}
		dropped++
	}
	return dropped, nil
}

// dropSeriesShell removes a series row, its seasons, and everything keyed by
// either. The caller has already moved anything worth keeping.
func dropSeriesShell(tx *sql.Tx, seriesID string) error {
	seasons, err := tx.Query(`SELECT id FROM item WHERE series_id = ? OR parent_id = ?`, seriesID, seriesID)
	if err != nil {
		return err
	}
	ids := []string{seriesID}
	for seasons.Next() {
		var id string
		seasons.Scan(&id)
		ids = append(ids, id)
	}
	seasons.Close()
	for _, id := range ids {
		for _, t := range twinTables {
			if _, err := tx.Exec("DELETE FROM "+t.table+" WHERE item_id = ?", id); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, id); err != nil {
			return err
		}
	}
	return nil
}

// looksUnnamed is a name the scanner gave from the filename — `Show - 2x11 -
// Title`, `Show S02E11` — rather than a title on its own.
func looksUnnamed(name string) bool {
	_, _, numbered := ParseEpisodeNumbering(name)
	return numbered
}
