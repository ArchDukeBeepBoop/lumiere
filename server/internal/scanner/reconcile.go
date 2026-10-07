package scanner

import (
	"database/sql"
	"path/filepath"
)

// reconcile settles the files a walk did not find.
//
// The scan was additive by design: a media drive that failed to come up looks
// exactly like a library whose files were all deleted, and the destructive
// reading of that is unrecoverable. So a file that moved got a fresh row at
// its new path, kept its old row at the old one, and the old folder went on
// listing something that was not there. The thumbnail went with the old row —
// the new one had never been scraped — which is the "moved content has no
// picture" complaint from the other side.
//
// Two things are done here, in order of how sure they are.
//
// A *move* is a missing file and a new file with the same name and the same
// size. That pairing is not a guess: two different videos with the same byte
// count and the same filename do not happen. The old row keeps its identity —
// its id, its watch state, its artwork, its provider match — and simply learns
// the new path and parents; the fresh row is dropped. Nothing is lost.
//
// A *deletion* is what remains, and it is deleted only under two guards. The
// walk must have opened the root, which Walk already insists on; and no more
// than a third of the library may vanish in one pass. Past that it is not a
// tidy-up, it is a mount that came up half empty, and the rows are left for a
// scan that can see them.
func (s *Scanner) reconcile(libraryID string, known, seen map[string]bool, result *Result) error {
	var missing []string
	for path := range known {
		if !seen[path] {
			missing = append(missing, path)
		}
	}
	if len(missing) == 0 {
		return nil
	}

	// Files this pass added, indexed by what identifies a moved file.
	added := map[moveKey]Found{}
	for _, file := range result.added {
		added[moveKey{filepath.Base(file.Path), file.Size}] = file
	}

	var gone []missingFile
	for _, path := range missing {
		var id string
		var size int64
		err := s.Store.DB.QueryRow(
			`SELECT id, COALESCE(size, 0) FROM item WHERE path = ?`, path,
		).Scan(&id, &size)
		if err != nil {
			continue
		}
		k := moveKey{filepath.Base(path), size}
		file, moved := added[k]
		if !moved && s.pass != nil {
			// Added by a library scanned earlier in this pass: a file moved
			// from this folder into that one.
			file, moved = s.pass.added[k]
		}
		if !moved || size == 0 {
			gone = append(gone, missingFile{id: id, path: path, key: k})
			continue
		}
		if err := s.adoptMove(id, file); err != nil {
			s.Log.Info("scan: could not record move", "from", path, "to", file.Path, "error", err)
			continue
		}
		s.Log.Info("scan: moved", "from", path, "to", file.Path)
		result.Moved++
		result.Added--
	}

	if s.pass != nil {
		// Settled at the end of the pass, once every library has been read:
		// the file may turn up in one scanned after this. See FinishPass.
		s.pass.deferred = append(s.pass.deferred, deferredLibrary{
			libraryID: libraryID, known: len(known), gone: gone,
		})
		return nil
	}
	s.settle(libraryID, len(known), gone, result)
	return nil
}

// settle removes what is still missing, under the third-of-a-library guard.
// Counted against what was known, not what is left, so a small library
// losing two files is still allowed to.
func (s *Scanner) settle(libraryID string, known int, gone []missingFile, result *Result) {
	if len(gone) == 0 {
		return
	}
	if len(gone)*3 > known {
		s.Log.Info("scan: refusing to remove most of a library in one pass",
			"library", libraryID, "missing", len(gone), "known", known)
		result.Missing += len(gone)
		return
	}
	for _, m := range gone {
		if err := s.removeFile(m.id); err != nil {
			s.Log.Info("scan: could not remove missing file", "id", m.id, "error", err)
			continue
		}
		result.Removed++
	}
}

// adoptMove gives the old row the new file's place and drops the new row.
func (s *Scanner) adoptMove(oldID string, file Found) error {
	newID := ItemID(file.Path)
	tx, err := s.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Everything about *where* it is comes from the fresh row, which the
	// layout rules have already placed; everything about *what* it is stays.
	// Read, then dropped, then written: one file is one row, and the old row
	// cannot take the path while the fresh one still holds it.
	var path, libraryID string
	var parentID, seriesID, typ sql.NullString
	var season, episode sql.NullInt64
	if err := tx.QueryRow(`
		SELECT path, library_id, parent_id, series_id, parent_index_number, index_number, type
		FROM item WHERE id = ?`, newID).Scan(
		&path, &libraryID, &parentID, &seriesID, &season, &episode, &typ); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, newID); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		UPDATE item SET path = ?, library_id = ?, parent_id = ?, series_id = ?,
		    parent_index_number = ?, index_number = ?, type = ?
		WHERE id = ?`,
		path, libraryID, parentID, seriesID, season, episode, typ, oldID); err != nil {
		return err
	}
	return tx.Commit()
}

// removeFile drops a file row and what hangs off it. Watch history is kept:
// a row in user_data for an id that no longer exists costs nothing, and the
// file may come back.
func (s *Scanner) removeFile(id string) error {
	tx, err := s.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, table := range []string{"image", "stream", "chapter", "segment", "item_value"} {
		if _, err := tx.Exec(`DELETE FROM `+table+` WHERE item_id = ?`, id); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, id); err != nil {
		return err
	}
	return tx.Commit()
}

// dropEmptyContainers removes seasons and series that a move or a removal
// left with nothing under them. Only ones the scanner made — a container with
// artwork or a provider match was somebody's show and stays for its metadata.
func dropEmptyContainers(db *sql.DB) (int, error) {
	dropped := 0
	for _, kind := range []string{"Season", "Series"} {
		res, err := db.Exec(`
			DELETE FROM item WHERE type = ? AND is_folder = 1
			  AND NOT EXISTS (SELECT 1 FROM item c WHERE c.parent_id = item.id)
			  -- Both linkage columns. An earlier merge rewrote parent_id and
			  -- left season_id and series_id pointing at the loser, so a
			  -- container empty by one column could still be named by the
			  -- other — and dropping it left ninety-two episodes with a
			  -- season that did not exist.
			  AND NOT EXISTS (SELECT 1 FROM item c WHERE c.season_id = item.id)
			  AND NOT EXISTS (SELECT 1 FROM item c WHERE c.series_id = item.id)
			  AND NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = item.id)
			  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = item.id AND v.kind LIKE 'provider:%')`,
			kind)
		if err != nil {
			return dropped, err
		}
		n, _ := res.RowsAffected()
		dropped += int(n)
	}
	return dropped, nil
}

// healSeasonLinks points an episode's season_id at the season it actually sits
// under, wherever the two disagree or the named season is gone.
//
// A duplicate-season merge rewrote parent_id to the kept season and left
// season_id on the dropped one. parent_id is the linkage the tree is drawn
// from, so it is the one to trust.
func healSeasonLinks(db *sql.DB) (int, error) {
	res, err := db.Exec(`
		UPDATE item SET season_id = parent_id
		WHERE type = 'Episode' AND parent_id IS NOT NULL
		  AND EXISTS (SELECT 1 FROM item p WHERE p.id = item.parent_id AND p.type = 'Season')
		  AND (season_id IS NULL OR season_id != parent_id)`)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return int(n), nil
}
