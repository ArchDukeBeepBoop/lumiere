package store

// Overview is the library described in a few numbers.
type Overview struct {
	Films, Shows, Episodes, Videos, Albums, Tracks int
	Bytes                                          int64
	WatchedFilms, WatchedEpisodes                  int
	AddedThisMonth                                 int
	Largest                                        []OverviewFile
}

// OverviewFile is one of the largest files.
type OverviewFile struct {
	Name  string
	Bytes int64
}

// LibraryOverview counts what the library holds and how much of it is
// watched. Informative, not a dashboard: a handful of numbers read once.
func (s *Store) LibraryOverview() (Overview, error) {
	var o Overview
	err := s.DB.QueryRow(`
		SELECT
		  (SELECT count(*) FROM item WHERE type = 'Movie' AND extra_type IS NULL),
		  (SELECT count(*) FROM item WHERE type = 'Series'),
		  (SELECT count(*) FROM item WHERE type = 'Episode' AND extra_type IS NULL),
		  (SELECT count(*) FROM item WHERE type = 'Video' AND extra_type IS NULL),
		  (SELECT count(*) FROM item WHERE type = 'MusicAlbum'),
		  (SELECT count(*) FROM item WHERE type = 'Audio'),
		  (SELECT COALESCE(sum(size), 0) FROM item WHERE is_folder = 0),
		  (SELECT count(*) FROM user_data u JOIN item i ON i.id = u.item_id WHERE u.played = 1 AND i.type = 'Movie'),
		  (SELECT count(*) FROM user_data u JOIN item i ON i.id = u.item_id WHERE u.played = 1 AND i.type = 'Episode'),
		  (SELECT count(*) FROM item WHERE is_folder = 0 AND extra_type IS NULL
		     AND date_created >= strftime('%Y-%m-01', 'now'))`).Scan(
		&o.Films, &o.Shows, &o.Episodes, &o.Videos, &o.Albums, &o.Tracks, &o.Bytes,
		&o.WatchedFilms, &o.WatchedEpisodes, &o.AddedThisMonth)
	if err != nil {
		return o, err
	}
	rows, err := s.DB.Query(`
		SELECT CASE WHEN type = 'Episode' AND COALESCE(series_name, '') <> ''
		            THEN series_name || ' — ' || name ELSE name END, size
		FROM item WHERE is_folder = 0 AND size IS NOT NULL ORDER BY size DESC LIMIT 5`)
	if err != nil {
		return o, err
	}
	defer rows.Close()
	for rows.Next() {
		var f OverviewFile
		if rows.Scan(&f.Name, &f.Bytes) == nil {
			o.Largest = append(o.Largest, f)
		}
	}
	return o, rows.Err()
}
