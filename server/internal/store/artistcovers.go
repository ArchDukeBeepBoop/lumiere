package store

import "strings"

// ArtistCovers answers "what picture can stand in for this artist?" for the
// artists that have no photo of their own: the newest album with a cover that is
// filed under them, credited to them as album artist, or carries a track naming
// them. Keyed by artist id and by lower-cased name, so a caller can look up
// either.
//
// Worked out in one pass over the albums and tracks in memory rather than per
// artist in SQL: the per-artist query took three seconds on the real library
// (seven hundred artists, each scanning every track's credits), and the Artists
// tab asks for all of them at once.
func (s *Store) ArtistCovers() (byID, byName map[string]string, err error) {
	type album struct {
		id   string
		year int
	}
	newest := func(m map[string]album, key string, a album) {
		if cur, ok := m[key]; !ok || a.year > cur.year {
			m[key] = a
		}
	}
	ids, names, credits := map[string]album{}, map[string]album{}, map[string]album{}
	covered := map[string]int{}

	rows, err := s.DB.Query(`
		SELECT al.id, COALESCE(al.parent_id, ''), COALESCE(al.album_artist, ''), COALESCE(al.production_year, 0)
		FROM item al
		WHERE al.type = 'MusicAlbum'
		  AND EXISTS (SELECT 1 FROM image g WHERE g.item_id = al.id AND g.kind = 'Primary')`)
	if err != nil {
		return nil, nil, err
	}
	for rows.Next() {
		var id, parent, artist string
		var year int
		if err := rows.Scan(&id, &parent, &artist, &year); err != nil {
			rows.Close()
			return nil, nil, err
		}
		a := album{id, year}
		covered[id] = year
		if parent != "" {
			newest(ids, parent, a)
		}
		if artist != "" {
			newest(names, strings.ToLower(artist), a)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}

	// A guest appears only in a track's credits; their newest such album stands in.
	tracks, err := s.DB.Query(`SELECT COALESCE(parent_id, ''), COALESCE(artists, '') FROM item WHERE type = 'Audio'`)
	if err != nil {
		return nil, nil, err
	}
	defer tracks.Close()
	for tracks.Next() {
		var parent, credited string
		if err := tracks.Scan(&parent, &credited); err != nil {
			return nil, nil, err
		}
		year, ok := covered[parent]
		if !ok {
			continue
		}
		for _, name := range strings.Split(credited, "|") {
			if name = strings.ToLower(strings.TrimSpace(name)); name != "" {
				newest(credits, name, album{parent, year})
			}
		}
	}
	if err := tracks.Err(); err != nil {
		return nil, nil, err
	}

	byID, byName = map[string]string{}, map[string]string{}
	for k, a := range ids {
		byID[k] = a.id
	}
	// An album filed under the artist's name beats one they only guest on.
	for _, m := range []map[string]album{credits, names} {
		for k, a := range m {
			byName[k] = a.id
		}
	}
	return byID, byName, nil
}
