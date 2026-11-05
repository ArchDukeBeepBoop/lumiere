package store

import (
	"sort"
	"strings"
)

// A music library's leaders: its artists ranked, and a cover for each genre.

// libraryScope is a library view and the folders behind it, as placeholders
// and arguments for `library_id IN (...)`.
func (s *Store) libraryScope(parentID string) (string, []any) {
	folders, _ := s.resolveFolders(parentID)
	ids := append([]string{parentID}, folders...)
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	return placeholders(len(ids)), args
}

// TopArtists is a library's artists, most played first — every play of a
// track that credits them — and, among equals, the most tracks here. Before
// anything has been played that is simply who the library holds most of,
// and the plays take over as they come. One id per name; "Various Artists"
// is a label, not an artist, and is left out.
//
// Two flat reads and a tally in Go, with the matching rule the SQL had: the
// album artist exactly, or the name anywhere in the artist tag — which is what
// credits Rihanna on "JAŸ-Z + Rihanna + Ye", where no separator would. The
// single query it replaces joined every artist to every track with instr()
// and took two seconds — twenty beside an artwork pass — for a shelf of ten.
func (s *Store) TopArtists(parentID string, limit int) ([]string, error) {
	in, scope := s.libraryScope(parentID)
	rows, err := s.DB.Query(`
		SELECT COALESCE(t.album_artist, ''), COALESCE(t.artists, ''), COALESCE(u.play_count, 0)
		FROM item t LEFT JOIN user_data u ON u.item_id = t.id
		WHERE t.type = 'Audio' AND t.library_id IN (`+in+`)`, scope...)
	if err != nil {
		return nil, err
	}
	var tracks []creditedTrack
	for rows.Next() {
		var albumArtist, artists string
		var plays int
		if err := rows.Scan(&albumArtist, &artists, &plays); err != nil {
			rows.Close()
			return nil, err
		}
		tracks = append(tracks, creditedTrack{albumArtist: albumArtist, artists: artists, plays: plays})
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	artists := map[string]artistRow{} // folded name → its lowest id and name
	rows, err = s.DB.Query(`SELECT id, name FROM item WHERE type = 'MusicArtist'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, name string
		if err := rows.Scan(&id, &name); err != nil {
			return nil, err
		}
		key := sqliteLower(name) // GROUP BY lower(name), as the SQL did
		if old, ok := artists[key]; !ok || id < old.id {
			artists[key] = artistRow{id: id, name: name}
		}
	}
	return rankArtists(tracks, artists, limit), rows.Err()
}

type creditedTrack struct {
	albumArtist, artists string
	plays                int
}

type artistRow struct{ id, name string }

// rankArtists orders artists by plays, then tracks, then name. Pure.
func rankArtists(tracks []creditedTrack, artists map[string]artistRow, limit int) []string {
	type tally struct {
		key           string
		plays, tracks int
	}
	var ranked []*tally
	for key, a := range artists {
		switch key {
		case "various artists", "various", "va":
			continue
		}
		t := &tally{key: key}
		for _, tr := range tracks {
			if tr.albumArtist == a.name || strings.Contains(tr.artists, a.name) {
				t.plays += tr.plays
				t.tracks++
			}
		}
		if t.tracks > 0 {
			ranked = append(ranked, t)
		}
	}
	sort.Slice(ranked, func(i, j int) bool {
		a, b := ranked[i], ranked[j]
		if a.plays != b.plays {
			return a.plays > b.plays
		}
		if a.tracks != b.tracks {
			return a.tracks > b.tracks
		}
		return a.key < b.key
	})
	var ids []string
	for _, t := range ranked {
		if len(ids) == limit {
			break
		}
		ids = append(ids, artists[t.key].id)
	}
	return ids
}

// GenreCovers picks an album for each music genre of a library, at random
// each time, keyed by the genre in lower case: the picture on its card.
func (s *Store) GenreCovers(parentID string) (map[string]string, error) {
	in, scope := s.libraryScope(parentID)
	rows, err := s.DB.Query(`
		SELECT lower(v.value), i.id FROM item i
		CROSS JOIN item_value v ON v.item_id = i.id AND v.kind = 'genre'
		WHERE i.type = 'MusicAlbum' AND i.library_id IN (`+in+`)
		  AND EXISTS (SELECT 1 FROM image m WHERE m.item_id = i.id AND m.kind = 'Primary')
		ORDER BY random()`, scope...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var genre, id string
		if err := rows.Scan(&genre, &id); err != nil {
			return nil, err
		}
		if _, seen := out[genre]; !seen {
			out[strings.ToLower(genre)] = id
		}
	}
	return out, rows.Err()
}
