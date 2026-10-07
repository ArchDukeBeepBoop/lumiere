package store

// ProbedStream is one track as this server's own probe reads it.
type ProbedStream struct {
	Index                   int
	Type, Codec, Profile    string
	Language, Title         string
	Default, Forced         bool
	Width, Height, BitDepth int
	Range                   string
	FrameRate               float64
	Channels, SampleRate    int
	Layout                  string
	BitRate                 int64
}

// PathItem is an item's id and file.
type PathItem struct{ ID, Path string }

// ItemsWithoutStreams lists videos with no tracks recorded and no failed probe.
func (s *Store) ItemsWithoutStreams(limit int) []PathItem {
	rows, err := s.DB.Query(`
		SELECT id, path FROM item i
		WHERE i.is_folder = 0 AND i.path IS NOT NULL AND i.path <> ''
		  AND i.type IN ('Movie', 'Episode', 'Video')
		  AND NOT EXISTS (SELECT 1 FROM stream s WHERE s.item_id = i.id)
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id AND v.kind = 'streams:failed')
		ORDER BY date_created DESC LIMIT ?`, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []PathItem
	for rows.Next() {
		var p PathItem
		if rows.Scan(&p.ID, &p.Path) == nil {
			out = append(out, p)
		}
	}
	return out
}

// WriteStreams records an item's tracks, replacing the embedded ones it had.
// External subtitle rows, which the probe of the file never sees, are kept.
func (s *Store) WriteStreams(itemID string, rows []ProbedStream) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM stream WHERE item_id = ? AND is_external = 0`, itemID); err != nil {
		return err
	}
	for _, r := range rows {
		display := r.Title
		if display == "" {
			display = r.Language
		}
		if _, err := tx.Exec(`INSERT OR REPLACE INTO stream (
			item_id, idx, type, codec, language, title, display_title, is_default, is_forced, is_external,
			width, height, bit_depth, video_range, video_range_type, profile, average_frame_rate, real_frame_rate,
			channels, sample_rate, channel_layout, bit_rate)
			VALUES (?,?,?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,?,?)`,
			itemID, r.Index, r.Type, r.Codec, nullStr(r.Language), nullStr(r.Title), nullStr(display),
			r.Default, r.Forced, nullInt(r.Width), nullInt(r.Height), nullInt(r.BitDepth),
			nullStr(r.Range), nullStr(r.Range), nullStr(r.Profile), nullFloat(r.FrameRate), nullFloat(r.FrameRate),
			nullInt(r.Channels), nullInt(r.SampleRate), nullStr(r.Layout), r.BitRate); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func nullStr(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func nullInt(v int) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullFloat(v float64) any {
	if v == 0 {
		return nil
	}
	return v
}
