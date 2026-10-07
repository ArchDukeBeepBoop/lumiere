package store

// SeriesNext is, for each film series under way, the next film to watch.
//
// A collection is "under way" once any of its films is watched. The next one
// is the first unwatched film after the latest watched one, in release order —
// so finishing Alien offers Aliens, and watching Aliens out of turn does not
// send you back to Alien. A collection with nothing watched after the last
// watched film offers nothing: it is finished, or you stopped on purpose.
// Films only; a show in a collection has its own Next Up.
func (s *Store) SeriesNext(limit int) ([]string, error) {
	rows, err := s.DB.Query(`
		SELECT l.parent_id, m.id, COALESCE(u.played, 0), COALESCE(u.last_played, '')
		FROM link l
		JOIN item b ON b.id = l.parent_id AND b.type = 'BoxSet'
		JOIN item m ON m.id = l.child_id AND m.type = 'Movie' AND m.extra_type IS NULL
		LEFT JOIN user_data u ON u.item_id = m.id
		ORDER BY l.parent_id, COALESCE(m.premiere_date, printf('%04d', m.production_year), '9999'), m.sort_name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	type film struct {
		id     string
		played bool
		last   string
	}
	collections := map[string][]film{}
	var order []string
	for rows.Next() {
		var c, id, last string
		var played int
		if rows.Scan(&c, &id, &played, &last) != nil {
			continue
		}
		if _, ok := collections[c]; !ok {
			order = append(order, c)
		}
		collections[c] = append(collections[c], film{id, played == 1, last})
	}
	type pick struct{ id, when string }
	var picks []pick
	seen := map[string]bool{}
	for _, c := range order {
		films := collections[c]
		lastWatched, when := -1, ""
		for i, f := range films {
			if f.played {
				lastWatched = i
				if f.last > when {
					when = f.last
				}
			}
		}
		if lastWatched < 0 {
			continue
		}
		for _, f := range films[lastWatched+1:] {
			if !f.played {
				if !seen[f.id] {
					seen[f.id] = true
					picks = append(picks, pick{f.id, when})
				}
				break
			}
		}
	}
	// Most recently continued first, as Next Up orders shows.
	for i := 1; i < len(picks); i++ {
		for j := i; j > 0 && picks[j].when > picks[j-1].when; j-- {
			picks[j], picks[j-1] = picks[j-1], picks[j]
		}
	}
	var ids []string
	for _, p := range picks {
		if len(ids) == limit {
			break
		}
		ids = append(ids, p.id)
	}
	return ids, rows.Err()
}

// NextInCollection is the film after this one in release order, in the first
// collection holding it that has one, and that collection's name.
func (s *Store) NextInCollection(itemID string) (nextID, collection string) {
	rows, err := s.DB.Query(`
		SELECT b.id, b.name FROM link l JOIN item b ON b.id = l.parent_id AND b.type = 'BoxSet'
		WHERE l.child_id = ? ORDER BY b.name`, itemID)
	if err != nil {
		return "", ""
	}
	type box struct{ id, name string }
	var boxes []box
	for rows.Next() {
		var b box
		rows.Scan(&b.id, &b.name)
		boxes = append(boxes, b)
	}
	rows.Close()
	for _, b := range boxes {
		members, err := s.DB.Query(`
			SELECT m.id FROM link l JOIN item m ON m.id = l.child_id AND m.type = 'Movie'
			WHERE l.parent_id = ?
			ORDER BY COALESCE(m.premiere_date, printf('%04d', m.production_year), '9999'), m.sort_name`, b.id)
		if err != nil {
			continue
		}
		var ids []string
		for members.Next() {
			var id string
			members.Scan(&id)
			ids = append(ids, id)
		}
		members.Close()
		for i, id := range ids {
			if id == itemID && i+1 < len(ids) {
				return ids[i+1], b.name
			}
		}
	}
	return "", ""
}
