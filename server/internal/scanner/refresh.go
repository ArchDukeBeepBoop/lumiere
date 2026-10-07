package scanner

import (
	"database/sql"
)

// Files replaced in place.
//
// The scanner reads a file once, when it first appears: a known path is
// skipped. So a broken download replaced by a good copy under the same name —
// One Piece 1124, all zeros, swapped for a real file — kept the reading the
// broken one got, and Library Health went on calling it unreadable until a
// full rescan that never came. The size is what gives it away: a file that
// changed size since it was read is re-read, cheaply, in the same walk.

// knownSizes is each file's size as last read, for the libraries' files.
func (s *Scanner) knownSizes(libraryID string) (map[string]int64, error) {
	rows, err := s.Store.DB.Query(`
		SELECT path, COALESCE(size, 0) FROM item
		WHERE library_id = ? AND path IS NOT NULL AND is_folder = 0`, libraryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	sizes := map[string]int64{}
	for rows.Next() {
		var path string
		var size int64
		if err := rows.Scan(&path, &size); err != nil {
			return nil, err
		}
		sizes[path] = size
	}
	return sizes, rows.Err()
}

// rereadChanged probes each changed file again and writes what it finds.
// Its streams are cleared so the next request reads them from the new file;
// its watch state, title and artwork are the item's and stay.
func (s *Scanner) rereadChanged(changed []Found) int {
	reread := 0
	for _, file := range changed {
		var probe Probe
		if s.FFprobe != "" {
			if p, err := ProbeFile(s.FFprobe, file.Path); err == nil {
				probe = p
			}
		}
		var ticks any
		if probe.DurationSeconds > 0 {
			ticks = int64(probe.DurationSeconds * 10_000_000)
		}
		if err := withTx(s.Store.DB, func(tx *sql.Tx) error {
			if _, err := tx.Exec(`
				UPDATE item SET size = ?, runtime_ticks = ?, container = ?, total_bitrate = ?
				WHERE path = ? AND is_folder = 0`,
				file.Size, ticks, nullString(probe.Container), nullInt(probe.Bitrate), file.Path); err != nil {
				return err
			}
			_, err := tx.Exec(`DELETE FROM stream WHERE item_id IN (
				SELECT id FROM item WHERE path = ? AND is_folder = 0)
				AND COALESCE(is_external, 0) = 0`, file.Path)
			return err
		}); err != nil {
			s.Log.Info("scan: could not re-read a changed file", "path", file.Path, "error", err)
			continue
		}
		s.Log.Info("scan: re-read a file that changed", "path", file.Path)
		reread++
	}
	return reread
}

func withTx(db *sql.DB, fn func(*sql.Tx) error) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit()
}
