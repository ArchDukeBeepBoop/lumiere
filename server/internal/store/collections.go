package store

import "database/sql"

// Where collections live.
//
// A BoxSet made here was inserted with no parent and no library, so it sat
// outside the Collections library: the client's sync of that library never
// saw it and swept it from the cache seconds after it was made. The home is
// read from the collections that are already there — the import filed them
// correctly — rather than from a name or a type that could differ.
func (s *Store) collectionsHome(q interface {
	QueryRow(string, ...any) *sql.Row
}) (parentID, libraryID string) {
	q.QueryRow(`
		SELECT parent_id, COALESCE(library_id, '') FROM item
		WHERE type = 'BoxSet' AND COALESCE(parent_id, '') <> ''
		  -- Not the private room's, which live in their own library: one of
		  -- those must never become where every new collection goes.
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = item.id AND v.kind = 'room:private')
		GROUP BY parent_id, library_id ORDER BY count(*) DESC LIMIT 1`).Scan(&parentID, &libraryID)
	return
}

// HomeStrayCollections files every collection with no parent into the
// Collections library. Returns how many moved.
func (s *Store) HomeStrayCollections() (int, error) {
	parent, library := s.collectionsHome(s.DB)
	if parent == "" {
		return 0, nil
	}
	res, err := s.DB.Exec(`
		UPDATE item SET parent_id = ?, library_id = NULLIF(?, '')
		WHERE type = 'BoxSet' AND COALESCE(parent_id, '') = ''`, parent, library)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return int(n), nil
}

// AddMissingLinks appends only the members not already there. Returns how
// many were added.
func (s *Store) AddMissingLinks(parentID string, childIDs []string) (int, error) {
	var fresh []string
	for _, child := range childIDs {
		var n int
		s.DB.QueryRow(`SELECT count(*) FROM link WHERE parent_id = ? AND child_id = ?`, parentID, child).Scan(&n)
		if n == 0 {
			fresh = append(fresh, child)
		}
	}
	if len(fresh) == 0 {
		return 0, nil
	}
	return len(fresh), s.AddLinks(parentID, fresh)
}

// SetItemValue replaces one kind of value on an item. Empty clears it.
func (s *Store) SetItemValue(itemID, kind, value string) {
	s.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = ?`, itemID, kind)
	if value != "" {
		s.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, ?, ?)`, itemID, kind, value)
	}
}

// CollectionPosters says whether a collection's poster is this server's to
// make — it has none, or the one it has was made here — and lists the first
// members' posters, in collection order, to make it from.
func (s *Store) CollectionPosters(id string) (ours bool, posters []string) {
	var have, made int
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = ? AND kind = 'Primary'`, id).Scan(&have)
	s.DB.QueryRow(`SELECT count(*) FROM item_value WHERE item_id = ? AND kind = 'art:mosaic'`, id).Scan(&made)
	if have > 0 && made == 0 {
		return false, nil
	}
	rows, err := s.DB.Query(`
		SELECT i.path FROM link l JOIN image i ON i.item_id = l.child_id AND i.kind = 'Primary' AND i.idx = 0
		WHERE l.parent_id = ? ORDER BY l.position LIMIT 4`, id)
	if err != nil {
		return true, nil
	}
	defer rows.Close()
	for rows.Next() {
		var p string
		rows.Scan(&p)
		posters = append(posters, p)
	}
	return true, posters
}

// PosterlessCollections lists collections with no poster at all.
func (s *Store) PosterlessCollections() []string {
	rows, err := s.DB.Query(`SELECT id FROM item b WHERE b.type = 'BoxSet'
		AND NOT EXISTS (SELECT 1 FROM image i WHERE i.item_id = b.id AND i.kind = 'Primary')`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		ids = append(ids, id)
	}
	return ids
}

// MergeCollection moves `from`'s members into `into` — only those it lacks —
// keeps the series id if `into` has none, and deletes `from`.
func (s *Store) MergeCollection(from, into string) (int, error) {
	rows, err := s.DB.Query(`SELECT child_id FROM link WHERE parent_id = ? ORDER BY position`, from)
	if err != nil {
		return 0, err
	}
	var members []string
	for rows.Next() {
		var m string
		rows.Scan(&m)
		members = append(members, m)
	}
	rows.Close()
	added, err := s.AddMissingLinks(into, members)
	if err != nil {
		return 0, err
	}
	s.DB.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value)
		SELECT ?, kind, value FROM item_value WHERE item_id = ? AND kind = 'tmdb_collection'
		AND NOT EXISTS (SELECT 1 FROM item_value WHERE item_id = ? AND kind = 'tmdb_collection')`, into, from, into)
	s.DB.Exec(`DELETE FROM item_value WHERE item_id = ?`, from)
	s.DB.Exec(`DELETE FROM image WHERE item_id = ?`, from)
	return added, s.DeleteContainer(from)
}

func (s *Store) linkedMembers(id string) []string {
	rows, err := s.DB.Query(`SELECT child_id FROM link WHERE parent_id = ? ORDER BY position`, id)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var m string
		rows.Scan(&m)
		out = append(out, m)
	}
	return out
}

// hydrateCollectionUnplayed counts the titles in each collection not yet
// watched — a film unplayed, or a show with an episode unplayed — so a
// collection's poster carries the same unwatched corner a show's does.
// Collections hold members by link, which the child-based count cannot see.
func (s *Store) hydrateCollectionUnplayed(byID map[string]*Item, in string, args []any) error {
	rows, err := s.DB.Query(`
		SELECT l.parent_id, COUNT(*) FROM link l
		JOIN item b ON b.id = l.parent_id AND b.type = 'BoxSet'
		JOIN item m ON m.id = l.child_id
		LEFT JOIN user_data u ON u.item_id = m.id
		WHERE l.parent_id IN (`+in+`) AND (
			(m.is_folder = 0 AND COALESCE(u.played, 0) = 0)
			OR (m.type = 'Series' AND EXISTS (
				SELECT 1 FROM item e LEFT JOIN user_data eu ON eu.item_id = e.id
				WHERE e.series_id = m.id AND e.type = 'Episode' AND e.extra_type IS NULL
				AND COALESCE(eu.played, 0) = 0)))
		GROUP BY l.parent_id`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var n int
		if rows.Scan(&id, &n) != nil {
			continue
		}
		if it, ok := byID[id]; ok {
			count := n
			if it.UserData == nil {
				it.UserData = &UserData{}
			}
			it.UserData.UnplayedItemCount = &count
		}
	}
	return rows.Err()
}
