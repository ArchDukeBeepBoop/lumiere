package store

import "time"

// A collection's watch order, arranged by hand, shared by every app (see the
// watch_order table). Ranks are spaced so one title can move between two
// neighbours without the rest being rewritten, as the Mac's were.

// WatchOrder is a collection's arranged titles, first to last; empty when
// none has been arranged.
func (s *Store) WatchOrder(collectionID string) ([]string, error) {
	rows, err := s.DB.Query(`SELECT item_id FROM watch_order WHERE collection_id = ? ORDER BY rank, item_id`, collectionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// SetWatchOrder replaces a collection's arrangement with [ids], in order; an
// empty list clears it (back to release order).
func (s *Store) SetWatchOrder(collectionID string, ids []string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM watch_order WHERE collection_id = ?`, collectionID); err != nil {
		return err
	}
	now := time.Now().UTC().Format(time.RFC3339)
	seen := map[string]bool{}
	for i, id := range ids {
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		if _, err := tx.Exec(`INSERT INTO watch_order (collection_id, item_id, rank, updated_at) VALUES (?, ?, ?, ?)`,
			collectionID, id, (i+1)*rankStride, now); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// rankStride is the gap between ranks, as the Mac's collectionRank had it.
const rankStride = 1024
