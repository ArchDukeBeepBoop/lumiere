package store

// The raw material for collection suggestions: which titles the movie
// database files under the same film series, which of this library's
// collections already stands for that series, and what those hold.

// TmdbGroup is one film series as this library holds it.
type TmdbGroup struct {
	TmdbID       string
	Members      []string // item ids of the titles here in that series
	FirstName    string   // a member's name, for a fallback label
	CollectionID string   // an existing collection for the series, if any
	Linked       map[string]bool
}

// TmdbGroups reads every title with a movie-database collection id.
func (s *Store) TmdbGroups() ([]TmdbGroup, error) {
	rows, err := s.DB.Query(`
		SELECT v.value, i.id, i.name FROM item_value v JOIN item i ON i.id = v.item_id
		WHERE v.kind = 'provider:TmdbCollection' AND v.value <> '' AND i.type IN ('Movie', 'Series')
		ORDER BY v.value, COALESCE(i.premiere_date, ''), i.sort_name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var groups []TmdbGroup
	index := map[string]int{}
	for rows.Next() {
		var tmdb, id, name string
		if rows.Scan(&tmdb, &id, &name) != nil {
			continue
		}
		at, ok := index[tmdb]
		if !ok {
			groups = append(groups, TmdbGroup{TmdbID: tmdb, FirstName: name, Linked: map[string]bool{}})
			at = len(groups) - 1
			index[tmdb] = at
		}
		groups[at].Members = append(groups[at].Members, id)
	}
	for i := range groups {
		g := &groups[i]
		s.DB.QueryRow(`SELECT v.item_id FROM item_value v JOIN item b ON b.id = v.item_id
			WHERE v.kind = 'tmdb_collection' AND v.value = ? AND b.type = 'BoxSet' LIMIT 1`, g.TmdbID).Scan(&g.CollectionID)
		if g.CollectionID == "" {
			continue
		}
		links, err := s.DB.Query(`SELECT child_id FROM link WHERE parent_id = ?`, g.CollectionID)
		if err != nil {
			return nil, err
		}
		for links.Next() {
			var child string
			links.Scan(&child)
			g.Linked[child] = true
		}
		links.Close()
	}
	return groups, rows.Err()
}

// TmdbIDsHeld is every movie-database film id this library has.
func (s *Store) TmdbIDsHeld() map[string]bool {
	held := map[string]bool{}
	rows, err := s.DB.Query(`SELECT value FROM item_value WHERE kind = 'provider:Tmdb'`)
	if err != nil {
		return held
	}
	defer rows.Close()
	for rows.Next() {
		var v string
		rows.Scan(&v)
		held[v] = true
	}
	return held
}

// SeriesCollection is a collection that knows its film series.
type SeriesCollection struct{ ID, Name, TmdbID string }

func (s *Store) CollectionsWithSeries() []SeriesCollection {
	rows, err := s.DB.Query(`SELECT b.id, b.name, v.value FROM item b
		JOIN item_value v ON v.item_id = b.id AND v.kind = 'tmdb_collection'
		WHERE b.type = 'BoxSet' AND v.value <> ''`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []SeriesCollection
	for rows.Next() {
		var c SeriesCollection
		rows.Scan(&c.ID, &c.Name, &c.TmdbID)
		out = append(out, c)
	}
	return out
}

// ItemsWithTmdb is every film or show here with that movie-database id.
func (s *Store) ItemsWithTmdb(id string) []string {
	rows, err := s.DB.Query(`SELECT v.item_id FROM item_value v JOIN item i ON i.id = v.item_id
		WHERE v.kind = 'provider:Tmdb' AND v.value = ? AND i.type IN ('Movie', 'Series')`, id)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var x string
		rows.Scan(&x)
		out = append(out, x)
	}
	return out
}

// EmptyCollectionsWithoutSeries are collections with no members, no series id
// and no failed lookup yet.
func (s *Store) EmptyCollectionsWithoutSeries() []SeriesCollection {
	rows, err := s.DB.Query(`SELECT b.id, b.name FROM item b WHERE b.type = 'BoxSet'
		AND NOT EXISTS (SELECT 1 FROM link WHERE parent_id = b.id)
		AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = b.id
		                AND v.kind IN ('tmdb_collection', 'tmdb_collection:searched'))`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []SeriesCollection
	for rows.Next() {
		var c SeriesCollection
		rows.Scan(&c.ID, &c.Name)
		out = append(out, c)
	}
	return out
}
