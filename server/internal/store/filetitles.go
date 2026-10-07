package store

import (
	"regexp"
	"strings"
)

// Episodes TMDB could not name, named from their own files.
//
// The naming pass matches an episode to TMDB's listing by season and episode
// number, and some shows are split differently there than on disk — Justice
// League's third season is Justice League Unlimited on TMDB, Gintama's
// seasons follow a different count. Those episodes kept the scanner's
// `Show - 3x03 - Kid Stuff`, when the title was sitting in the filename all
// along. Only once TMDB has been asked and had nothing: a title from the
// provider is the better one, and this is the fallback, never the first try.

// filenameTitle reads the title after a season-and-episode marker:
// `Show - 3x03 - Kid Stuff` and `Show - S02E17 - Lake Laogai` give the part
// after the marker. Pure, so it can be tested against real names.
var filenameTitle = regexp.MustCompile(`(?i)(?:\b\d{1,2}x\d{1,4}|\bS\d{1,2}E\d{1,4})\s*-\s*(.+)$`)

// TitleFromFilename is the episode title a filename carries, if any.
func TitleFromFilename(name string) (string, bool) {
	match := filenameTitle.FindStringSubmatch(name)
	if match == nil {
		return "", false
	}
	title := strings.TrimSpace(match[1])
	// A bare number or a release tag is not a title.
	if title == "" || strings.Trim(title, "0123456789 ") == "" {
		return "", false
	}
	return title, true
}

// TitleUnmatchedEpisodes renames every episode TMDB has answered for — or had
// nothing for — that still wears its filename, to the title in that filename.
// Locked names are left alone. Returns how many were renamed.
func (s *Store) TitleUnmatchedEpisodes() (int, error) {
	rows, err := s.DB.Query(`
		SELECT id, name FROM item i
		WHERE type = 'Episode'
		  AND EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id
		              AND v.kind IN ('provider:none', 'episode:enriched'))
		  AND NOT EXISTS (SELECT 1 FROM item_value l WHERE l.item_id = i.id
		                  AND l.kind IN ('lock:name', 'lock:*'))`)
	if err != nil {
		return 0, err
	}
	type rename struct{ id, title string }
	var renames []rename
	for rows.Next() {
		var id, name string
		if err := rows.Scan(&id, &name); err != nil {
			rows.Close()
			return 0, err
		}
		if !looksUnnamed(name) {
			continue
		}
		if title, ok := TitleFromFilename(name); ok {
			renames = append(renames, rename{id, title})
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for _, r := range renames {
		if _, err := s.DB.Exec(`UPDATE item SET name = ?, sort_name = ? WHERE id = ?`,
			r.title, r.title, r.id); err != nil {
			return 0, err
		}
	}
	return len(renames), nil
}

// TitleAllFromFilenames is the Library Health fix for "Episodes named after
// their file": every such episode takes the title its filename carries,
// whether or not the naming pass ever reached it. Some never will — a show
// matched to the wrong entry ("Dark Matter" for files that say "Dark") or
// split differently on the movie database. The name it had is kept beside it,
// so UndoFileTitles puts every one back. Locked names are left alone.
func (s *Store) TitleAllFromFilenames() (int, error) {
	rows, err := s.DB.Query(`
		SELECT id, name FROM item i
		WHERE type = 'Episode' AND extra_type IS NULL
		  AND NOT EXISTS (SELECT 1 FROM item_value l WHERE l.item_id = i.id
		                  AND l.kind IN ('lock:name', 'lock:*'))`)
	if err != nil {
		return 0, err
	}
	type rename struct{ id, old, title string }
	var renames []rename
	for rows.Next() {
		var id, name string
		if rows.Scan(&id, &name) != nil || !looksUnnamed(name) {
			continue
		}
		if title, ok := TitleFromFilename(name); ok {
			renames = append(renames, rename{id, name, title})
		}
	}
	rows.Close()
	tx, err := s.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	for _, r := range renames {
		if _, err := tx.Exec(`INSERT OR REPLACE INTO item_value (item_id, kind, value) VALUES (?, 'name:before-file-title', ?)`, r.id, r.old); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(`UPDATE item SET name = ?, sort_name = ? WHERE id = ?`, r.title, r.title, r.id); err != nil {
			return 0, err
		}
	}
	return len(renames), tx.Commit()
}

// UndoFileTitles restores every name TitleAllFromFilenames replaced.
func (s *Store) UndoFileTitles() (int, error) {
	res, err := s.DB.Exec(`
		UPDATE item SET name = v.value, sort_name = v.value
		FROM (SELECT item_id, value FROM item_value WHERE kind = 'name:before-file-title') v
		WHERE item.id = v.item_id`)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	s.DB.Exec(`DELETE FROM item_value WHERE kind = 'name:before-file-title'`)
	return int(n), nil
}
