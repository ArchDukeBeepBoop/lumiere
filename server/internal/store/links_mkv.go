package store

import (
	"database/sql"
	"time"

	"lumiere-server/internal/media"
)

// RecordSegment stores what a file's header said. See media.ReadSegment.
func (s *Store) RecordSegment(itemID string, seg media.Segment) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	ordered := 0
	if seg.Ordered {
		ordered = 1
	}
	if _, err := tx.Exec(`
		INSERT INTO mkv_segment (item_id, uid, ordered, read_at) VALUES (?, ?, ?, ?)
		ON CONFLICT(item_id) DO UPDATE SET uid = excluded.uid, ordered = excluded.ordered, read_at = excluded.read_at`,
		itemID, seg.UID, ordered, time.Now().UTC().Format(time.RFC3339)); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM mkv_link WHERE item_id = ?`, itemID); err != nil {
		return err
	}
	for i, c := range seg.Chapters {
		var link any
		if c.LinkUID != "" {
			link = c.LinkUID
		}
		if _, err := tx.Exec(`
			INSERT INTO mkv_link (item_id, position, start_ns, end_ns, link_uid, title)
			VALUES (?, ?, ?, ?, ?, ?)`, itemID, i, c.StartNS, c.EndNS, link, c.Title); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// SegmentsToIndex lists Matroska files the header has not been read from.
func (s *Store) SegmentsToIndex(limit int) ([][2]string, error) {
	rows, err := s.DB.Query(`
		SELECT i.id, i.path FROM item i
		WHERE i.is_folder = 0 AND i.path LIKE '%.mkv'
		  AND NOT EXISTS (SELECT 1 FROM mkv_segment m WHERE m.item_id = i.id)
		ORDER BY i.date_created DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out [][2]string
	for rows.Next() {
		var id, path string
		if err := rows.Scan(&id, &path); err != nil {
			return nil, err
		}
		out = append(out, [2]string{id, path})
	}
	return out, rows.Err()
}

// PlayRange is one stretch of an ordered edition, resolved to a file.
type PlayRange struct {
	ItemID   string  `json:"ItemId,omitempty"`
	Title    string  `json:"Title,omitempty"`
	StartSec float64 `json:"Start"`
	EndSec   float64 `json:"End"`
	// LinkUID is set on a borrowed range. Resolved says whether a file with
	// that UID is in the library; a false here is the release's opening
	// missing from beside the episode.
	LinkUID  string `json:"LinkUid,omitempty"`
	Resolved bool   `json:"Resolved"`
	// Path is the borrowed file on disk, for a client on the same machine
	// that can open it directly rather than stream it back through here.
	Path string `json:"Path,omitempty"`
}

// LinkedChapters is an item's ordered edition, each borrowed range resolved
// to the item that carries it. Nil where the file has no ordered edition.
func (s *Store) LinkedChapters(itemID string) ([]PlayRange, error) {
	var ordered int
	if err := s.DB.QueryRow(`SELECT ordered FROM mkv_segment WHERE item_id = ?`, itemID).Scan(&ordered); err != nil || ordered == 0 {
		return nil, nil
	}
	rows, err := s.DB.Query(`
		SELECT l.start_ns, l.end_ns, COALESCE(l.link_uid, ''), COALESCE(l.title, ''),
		       COALESCE(m.item_id, ''), COALESCE(i.path, '')
		FROM mkv_link l
		LEFT JOIN mkv_segment m ON m.uid = l.link_uid
		LEFT JOIN item i ON i.id = m.item_id
		WHERE l.item_id = ? ORDER BY l.position`, itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PlayRange
	for rows.Next() {
		var startNS, endNS int64
		var uid, title, linked, path string
		if err := rows.Scan(&startNS, &endNS, &uid, &title, &linked, &path); err != nil {
			return nil, err
		}
		r := PlayRange{
			Title: title, StartSec: float64(startNS) / 1e9, EndSec: float64(endNS) / 1e9,
			LinkUID: uid, Resolved: true,
		}
		switch {
		case uid == "":
			r.ItemID = itemID
		case linked != "":
			r.ItemID = linked
			r.Path = path
		default:
			r.Resolved = false
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// UnresolvedLinks counts the items whose ordered edition names a segment the
// library does not have — a release shipped without its opening and ending.
func (s *Store) UnresolvedLinks() (int, error) {
	var n int
	err := s.DB.QueryRow(`
		SELECT COUNT(DISTINCT l.item_id) FROM mkv_link l
		WHERE l.link_uid IS NOT NULL
		  AND NOT EXISTS (SELECT 1 FROM mkv_segment m WHERE m.uid = l.link_uid)
		  AND EXISTS (SELECT 1 FROM item i WHERE i.id = l.item_id)`).Scan(&n)
	return n, err
}

var _ = sql.ErrNoRows
