package store

import (
	"database/sql"
	"encoding/json"
	"time"
)

// Removal: taking something out of the library, with or without its file.
//
// Two operations, deliberately unlike each other. *Remove* moves the row into
// removed_item — the file is untouched, every query stops seeing it, and
// Restore puts it back exactly. *Delete* sends the file to the Trash and drops
// the row for good. Both cascade: a series takes its seasons and episodes, a
// season its episodes, because a show with no episodes is not something
// anyone meant to keep.
//
// This is the one place the app touches media on disk. It was designed never
// to, and that stance is now a switch rather than a rule — see the client's
// Preference.allowsDeletion — but the server still refuses to unlink: the
// Trash is where a mistake can be undone.

// Descendants lists an item and everything under it, deepest last.
func (s *Store) Descendants(id string) ([]string, error) {
	ids := []string{id}
	frontier := []string{id}
	for len(frontier) > 0 {
		var next []string
		for _, parent := range frontier {
			rows, err := s.DB.Query(`
				SELECT id FROM item
				WHERE parent_id = ? OR series_id = ? OR season_id = ?`, parent, parent, parent)
			if err != nil {
				return nil, err
			}
			for rows.Next() {
				var child string
				if err := rows.Scan(&child); err != nil {
					rows.Close()
					return nil, err
				}
				if child != parent && !contains(ids, child) {
					ids = append(ids, child)
					next = append(next, child)
				}
			}
			rows.Close()
		}
		frontier = next
	}
	return ids, nil
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

// Remove takes an item and its descendants out of the library, keeping the
// files. Returns how many rows moved.
func (s *Store) Remove(id string) (int, error) {
	ids, err := s.Descendants(id)
	if err != nil {
		return 0, err
	}
	tx, err := s.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	now := time.Now().UTC().Format(time.RFC3339)
	moved := 0
	for _, itemID := range ids {
		row, err := rowJSON(tx, itemID)
		if err != nil {
			return 0, err
		}
		if row == "" {
			continue
		}
		if _, err := tx.Exec(`
			INSERT OR REPLACE INTO removed_item (id, removed_at, row) VALUES (?, ?, ?)`,
			itemID, now, row); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, itemID); err != nil {
			return 0, err
		}
		moved++
	}
	return moved, tx.Commit()
}

// Restore puts a removed item — and whatever was removed with it in the same
// act — back. Returns how many rows came back.
func (s *Store) Restore(id string) (int, error) {
	var removedAt string
	if err := s.DB.QueryRow(`SELECT removed_at FROM removed_item WHERE id = ?`, id).Scan(&removedAt); err != nil {
		return 0, err
	}
	// Everything removed in the same second as this one: that is the cascade
	// it came with, and half a show restored is worse than none.
	rows, err := s.DB.Query(`SELECT id, row FROM removed_item WHERE removed_at = ?`, removedAt)
	if err != nil {
		return 0, err
	}
	type removed struct{ id, row string }
	var batch []removed
	for rows.Next() {
		var r removed
		if err := rows.Scan(&r.id, &r.row); err != nil {
			rows.Close()
			return 0, err
		}
		batch = append(batch, r)
	}
	rows.Close()

	tx, err := s.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	restored := 0
	for _, r := range batch {
		if err := insertRowJSON(tx, r.row); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(`DELETE FROM removed_item WHERE id = ?`, r.id); err != nil {
			return 0, err
		}
		restored++
	}
	return restored, tx.Commit()
}

// Removed lists what can be restored: the top of each cascade, newest first.
type RemovedItem struct {
	ID        string `json:"Id"`
	Name      string `json:"Name"`
	Type      string `json:"Type"`
	Path      string `json:"Path,omitempty"`
	RemovedAt string `json:"RemovedAt"`
	// Members is how many rows went with it.
	Members int `json:"Members"`
}

func (s *Store) Removed() ([]RemovedItem, error) {
	rows, err := s.DB.Query(`SELECT id, removed_at, row FROM removed_item ORDER BY removed_at DESC, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	type raw struct {
		id, at string
		fields map[string]any
	}
	var all []raw
	for rows.Next() {
		var r raw
		var row string
		if err := rows.Scan(&r.id, &r.at, &row); err != nil {
			return nil, err
		}
		json.Unmarshal([]byte(row), &r.fields)
		all = append(all, r)
	}
	// One entry per cascade: the row whose parent is not itself removed.
	removedIDs := map[string]bool{}
	for _, r := range all {
		removedIDs[r.id] = true
	}
	counts := map[string]int{}
	for _, r := range all {
		counts[r.at]++
	}
	var out []RemovedItem
	for _, r := range all {
		parent, _ := r.fields["parent_id"].(string)
		series, _ := r.fields["series_id"].(string)
		if removedIDs[parent] || removedIDs[series] {
			continue
		}
		name, _ := r.fields["name"].(string)
		kind, _ := r.fields["type"].(string)
		path, _ := r.fields["path"].(string)
		out = append(out, RemovedItem{
			ID: r.id, Name: name, Type: kind, Path: path, RemovedAt: r.at, Members: counts[r.at],
		})
	}
	return out, nil
}

// PathsUnder lists the files an item and its descendants point at, for the
// Trash. Folders with a path — a series' own folder — are included so a
// deleted show goes as one thing.
func (s *Store) PathsUnder(id string) ([]string, []string, error) {
	ids, err := s.Descendants(id)
	if err != nil {
		return nil, nil, err
	}
	var paths []string
	for _, itemID := range ids {
		var path sql.NullString
		s.DB.QueryRow(`SELECT path FROM item WHERE id = ?`, itemID).Scan(&path)
		if path.Valid && path.String != "" {
			paths = append(paths, path.String)
		}
	}
	return ids, paths, nil
}

// Purge drops rows and everything hanging off them. The files are the
// caller's business — see media.Trash.
func (s *Store) Purge(ids []string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, id := range ids {
		for _, table := range []string{"image", "stream", "chapter", "segment", "item_value", "user_data"} {
			if _, err := tx.Exec(`DELETE FROM `+table+` WHERE item_id = ?`, id); err != nil {
				return err
			}
		}
		for _, q := range []string{
			`DELETE FROM link WHERE child_id = ? OR parent_id = ?`,
		} {
			if _, err := tx.Exec(q, id, id); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, id); err != nil {
			return err
		}
		if _, err := tx.Exec(`DELETE FROM removed_item WHERE id = ?`, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// rowJSON reads one item row as a JSON object of column -> value.
func rowJSON(tx *sql.Tx, id string) (string, error) {
	rows, err := tx.Query(`SELECT * FROM item WHERE id = ?`, id)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	if !rows.Next() {
		return "", nil
	}
	columns, _ := rows.Columns()
	values := make([]any, len(columns))
	pointers := make([]any, len(columns))
	for i := range values {
		pointers[i] = &values[i]
	}
	if err := rows.Scan(pointers...); err != nil {
		return "", err
	}
	fields := map[string]any{}
	for i, column := range columns {
		if b, ok := values[i].([]byte); ok {
			fields[column] = string(b)
		} else {
			fields[column] = values[i]
		}
	}
	encoded, err := json.Marshal(fields)
	return string(encoded), err
}
