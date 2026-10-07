package store

// EpisodeTarget is one episode that has no picture, addressed the way a provider
// can find it: by season and episode number.
type EpisodeTarget struct {
	ID      string
	Season  int
	Episode int
}

// EpisodesWithoutImages lists a series' episodes that have no Primary image.
//
// Only the ones missing a picture, because that is the whole safety property of
// the backfill: an episode whose still Jellyfin already scraped, or that carries
// a frame grabbed from the file itself, is left alone. A fetch that replaced
// those would be undoing work rather than adding any.
func (s *Store) EpisodesWithoutImages(seriesID string) ([]EpisodeTarget, error) {
	rows, err := s.DB.Query(`
		SELECT id, parent_index_number, index_number
		FROM item
		WHERE series_id = ? AND type = 'Episode' AND extra_type IS NULL
		  AND parent_index_number IS NOT NULL AND index_number IS NOT NULL
		  AND NOT EXISTS (
			SELECT 1 FROM image g WHERE g.item_id = item.id AND g.kind = 'Primary'
		  )
		ORDER BY parent_index_number, index_number`, seriesID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []EpisodeTarget
	for rows.Next() {
		var t EpisodeTarget
		if err := rows.Scan(&t.ID, &t.Season, &t.Episode); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// ProviderID returns one of an item's scraped ids — "Tmdb", "Tvdb", "Imdb".
//
// Empty rather than an error when the item has none: a series nobody has
// identified is an ordinary case, not a failure, and every caller has something
// sensible to do about it.
func (s *Store) ProviderID(itemID, provider string) (string, error) {
	var value string
	err := s.DB.QueryRow(
		`SELECT value FROM item_value WHERE item_id = ? AND kind = ?`,
		itemID, "provider:"+provider,
	).Scan(&value)
	if err != nil && err.Error() == "sql: no rows in result set" {
		return "", nil
	}
	return value, err
}
