package store

// MusicGenres lists the genres present in a music library, by name.
//
// Jellyfin serves these as items with ids of their own. This server has no genre
// rows — a genre here is a value on an item, not a thing — so the name is the
// id, which is also what filtering takes: `/Items?Genres=` matches on the name.
// One spelling, and no id that can drift out of step with the value it stands
// for.
func (s *Store) MusicGenres(parentID string) ([]string, error) {
	return s.genres(parentID, "'Audio', 'MusicAlbum'")
}

// VideoGenres is the same for films and shows: the genre filter's choices.
func (s *Store) VideoGenres(parentID string) ([]string, error) {
	return s.genres(parentID, "'Movie', 'Series', 'Video'")
}

func (s *Store) genres(parentID, types string) ([]string, error) {
	args := []any{}
	scope := ""
	if parentID != "" {
		folders, err := s.resolveFolders(parentID)
		if err != nil {
			return nil, err
		}
		ids := append([]string{parentID}, folders...)
		scope = ` AND i.library_id IN (` + placeholders(len(ids)) + `)`
		for _, id := range ids {
			args = append(args, id)
		}
	}

	rows, err := s.DB.Query(`
		SELECT DISTINCT v.value
		FROM item_value v
		JOIN item i ON i.id = v.item_id
		WHERE v.kind = 'genre' AND i.type IN (`+types+`)`+scope+`
		ORDER BY v.value COLLATE NOCASE`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		out = append(out, name)
	}
	return out, rows.Err()
}
