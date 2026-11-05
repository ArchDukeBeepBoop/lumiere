package scanner

import (
	"database/sql"
)

// Music genres, from each track's genre tag.
//
// The scan read title, artist, album and year from a track and left its
// genre behind, so the Genres tab of a 2,303-track library listed nothing.
// A track's genres are kept as the video genres are — item_value rows of
// kind "genre" — and its album takes the genres of its tracks, so both the
// tab and an album's page have them.

// genreRead marks a track whose tag has been read, genre or none, so a
// library of untagged files is not probed again on every pass.
const genreRead = "genre:read"

// writeGenres files a track's genres, and its album's.
func writeGenres(db *sql.DB, trackID, albumID string, genres []string) {
	for _, g := range genres {
		db.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?, 'genre', ?)`, trackID, g)
		if albumID != "" {
			db.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?, 'genre', ?)`, albumID, g)
		}
	}
	db.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?, ?, '1')`, trackID, genreRead)
}

// fillMusicGenres reads the genre tag of tracks filed before genres were
// read — once each; returns how many it read.
func (s *Scanner) fillMusicGenres(libraryID string) int {
	rows, err := s.Store.DB.Query(`SELECT id, path, COALESCE(parent_id, '') FROM item i
		WHERE library_id = ? AND type = 'Audio' AND path IS NOT NULL AND path <> ''
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id AND v.kind = ?)`, libraryID, genreRead)
	if err != nil {
		return 0
	}
	type track struct{ id, path, album string }
	var todo []track
	for rows.Next() {
		var t track
		rows.Scan(&t.id, &t.path, &t.album)
		todo = append(todo, t)
	}
	rows.Close()
	for _, t := range todo {
		writeGenres(s.Store.DB, t.id, t.album, s.musicTags(t.path).Genres)
	}
	if len(todo) > 0 {
		s.Log.Info("music: genres read", "library", libraryID, "tracks", len(todo))
	}
	return len(todo)
}
