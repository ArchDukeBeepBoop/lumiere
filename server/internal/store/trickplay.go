package store

// PreviewCandidate is a video with no scrubbing previews yet.
type PreviewCandidate struct {
	ID, Path       string
	RuntimeSeconds float64
}

const metaPreviewFailed = "trickplay:failed"

// PreviewCandidates lists videos with no previews and no failure recorded,
// newest first — what was added last is what is about to be watched.
func (s *Store) PreviewCandidates(limit int) ([]PreviewCandidate, error) {
	rows, err := s.DB.Query(`
		SELECT id, path, runtime_ticks FROM item
		WHERE is_folder = 0 AND path IS NOT NULL AND path <> ''
		  AND type IN ('Movie', 'Episode', 'Video') AND extra_type IS NULL
		  AND runtime_ticks > 600000000
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = item.id
		                  AND v.kind IN ('trickplay', '`+metaPreviewFailed+`'))
		ORDER BY date_created DESC
		LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PreviewCandidate
	for rows.Next() {
		var c PreviewCandidate
		var ticks int64
		if err := rows.Scan(&c.ID, &c.Path, &ticks); err != nil {
			return nil, err
		}
		c.RuntimeSeconds = float64(ticks) / 1e7
		out = append(out, c)
	}
	return out, rows.Err()
}

// PreviewCounts is how many videos have previews, of how many could.
func (s *Store) PreviewCounts() (made, total int) {
	s.DB.QueryRow(`SELECT count(*) FROM item_value WHERE kind = 'trickplay'`).Scan(&made)
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE is_folder = 0 AND path IS NOT NULL
		AND path <> '' AND type IN ('Movie', 'Episode', 'Video') AND extra_type IS NULL
		AND runtime_ticks > 600000000`).Scan(&total)
	return
}

// PreviewFailed records a file previews could not be made from, against its
// fingerprint, so it is not tried every night. Cleared when the file changes
// — see the detail handler — or by hand.
func (s *Store) PreviewFailed(id, fingerprint string) {
	s.SetItemValue(id, metaPreviewFailed, fingerprint)
}

// ItemValue reads one kind of value on an item, or "".
func (s *Store) ItemValue(id, kind string) string {
	var v string
	s.DB.QueryRow(`SELECT value FROM item_value WHERE item_id = ? AND kind = ?`, id, kind).Scan(&v)
	return v
}
