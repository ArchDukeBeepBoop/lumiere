package store

import (
	"strings"
	"time"
)

// WatchChange is one row this server wrote that Jellyfin has not been told
// about.
type WatchChange struct {
	ItemID        string
	Played        bool
	PositionTicks int64
	IsFavorite    bool
	UpdatedAt     time.Time
}

// LocalWatchState returns everything written here since the last import or
// export.
//
// `source = 'local'` is the whole definition, and it is the same marker the
// import rule reads. That symmetry is the point: a row is local exactly as long
// as this server is the only one that knows about it, which is exactly as long
// as the import must not overwrite it and the export still has work to do.
func (s *Store) LocalWatchState() ([]WatchChange, error) {
	rows, err := s.DB.Query(`
		SELECT item_id, played, position_ticks, is_favorite, updated_at
		FROM user_data WHERE source = 'local'
		ORDER BY updated_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []WatchChange
	for rows.Next() {
		var c WatchChange
		var updated string
		if err := rows.Scan(&c.ItemID, &c.Played, &c.PositionTicks,
			&c.IsFavorite, &updated); err != nil {
			return nil, err
		}
		c.UpdatedAt = parseStamp(updated)
		out = append(out, c)
	}
	return out, rows.Err()
}

// MarkExported records that Jellyfin now holds this row too.
//
// The row stops being local, which is correct rather than a loss: the values on
// both sides are now identical, so a later import refreshing it changes nothing.
// Leaving it marked local would make every export push the same rows forever.
//
// Not straight to 'jellyfin' any more. Jellyfin keeps watch state in memory
// and writes it to its database on its own time, so the next import could read
// the value from before the push — and a 'jellyfin' row is one the import
// always refreshes, which rolled a just-sent resume point back. 'exported' is
// protected like a local row until Jellyfin's copy is the later one, and is
// not pushed again. See importer.overwriteLocal.
//
// Only if unchanged since it was read: progress written during the push is
// newer than what was sent, and stays local to go next time.
func (s *Store) MarkExported(itemID string, sent time.Time) error {
	_, err := s.DB.Exec(
		`UPDATE user_data SET source = 'exported' WHERE item_id = ? AND source = 'local'
		 AND abs(strftime('%s', updated_at) - ?) < 1`, itemID, sent.Unix())
	return err
}

// ExportCounts is what the Jellyfin sender reports: rows waiting to go, and
// items Jellyfin was found not to have.
func (s *Store) ExportCounts() (waiting, unmatched int) {
	s.DB.QueryRow(`SELECT count(*) FROM user_data WHERE source = 'local' AND item_id NOT IN
		(SELECT item_id FROM item_value WHERE kind IN ('export:unmatched', 'export:private'))`).Scan(&waiting)
	s.DB.QueryRow(`SELECT count(*) FROM item_value WHERE kind = 'export:unmatched'`).Scan(&unmatched)
	return
}

// LocalWatchStateSettled is LocalWatchState without anything written in the
// last `quiet`: a film being watched reports its position every ten seconds,
// and sending each of those would be a stream of stop reports to Jellyfin for
// one evening's viewing. Items Jellyfin does not have are left out.
func (s *Store) LocalWatchStateSettled(quiet time.Duration) ([]WatchChange, error) {
	all, err := s.LocalWatchState()
	if err != nil {
		return nil, err
	}
	unmatched := map[string]bool{}
	if rows, err := s.DB.Query(`SELECT item_id FROM item_value WHERE kind IN ('export:unmatched', 'export:private')`); err == nil {
		for rows.Next() {
			var id string
			rows.Scan(&id)
			unmatched[id] = true
		}
		rows.Close()
	}
	cutoff := time.Now().UTC().Add(-quiet)
	var out []WatchChange
	for _, c := range all {
		if c.UpdatedAt.After(cutoff) || unmatched[c.ItemID] {
			continue
		}
		out = append(out, c)
	}
	return out, nil
}

// UnmatchedExports are the items set aside because Jellyfin had no match.
func (s *Store) UnmatchedExports() []string {
	rows, err := s.DB.Query(`SELECT item_id FROM item_value WHERE kind = 'export:unmatched'`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		out = append(out, id)
	}
	return out
}

// ItemPath is an item's file path, for matching it to Jellyfin's by path.
func (s *Store) ItemPath(itemID string) string {
	var path string
	s.DB.QueryRow(`SELECT COALESCE(path, '') FROM item WHERE id = ?`, itemID).Scan(&path)
	return path
}

// AnyAccountID returns the single account this server serves.
//
// Single-user by design (§9.8), so "the account" is a meaningful phrase here in
// a way it would not be on Jellyfin.
func (s *Store) AnyAccountID() (string, error) {
	var id string
	err := s.DB.QueryRow(`SELECT id FROM account ORDER BY username LIMIT 1`).Scan(&id)
	return id, err
}

func parseStamp(raw string) time.Time {
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02 15:04:05"} {
		if t, err := time.Parse(layout, raw); err == nil {
			return t.UTC()
		}
	}
	return time.Time{}
}

// MetaLookupSkipped lists the libraries the naming pass leaves alone.
const MetaLookupSkipped = "metadata_skip_libraries"

// MetaExportExcluded lists the libraries — the ids clients know them by —
// whose watch state is not sent to Jellyfin. Set by the app from its private
// libraries, unless it is told to include them.
const MetaExportExcluded = "jellyfin_export_excluded_libraries"

// SetExportExcluded replaces the excluded libraries, and releases anything
// set aside under the old list so it is judged again.
func (s *Store) SetExportExcluded(viewIDs []string) error {
	if err := s.SetMeta(MetaExportExcluded, strings.Join(viewIDs, ",")); err != nil {
		return err
	}
	_, err := s.DB.Exec(`DELETE FROM item_value WHERE kind = 'export:private'`)
	return err
}

// ExcludedFromExport says whether an item lives in an excluded library,
// directly or through its show. A library's items carry its physical folder's
// id, not the id clients use, so both are checked through library_folder.
func (s *Store) ExcludedFromExport(itemID string) bool {
	raw, _ := s.Meta(MetaExportExcluded)
	if raw == "" {
		return false
	}
	views := strings.Split(raw, ",")
	args := []any{itemID, itemID}
	marks := strings.TrimSuffix(strings.Repeat("?,", len(views)), ",")
	for _, v := range views {
		args = append(args, v)
	}
	for _, v := range views {
		args = append(args, v)
	}
	var n int
	s.DB.QueryRow(`
		SELECT count(*) FROM item i
		WHERE (i.id = ? OR i.id = (SELECT series_id FROM item WHERE id = ?))
		  AND (i.library_id IN (`+marks+`)
		       OR i.library_id IN (SELECT folder_id FROM library_folder WHERE view_id IN (`+marks+`)))`,
		args...).Scan(&n)
	return n > 0
}
