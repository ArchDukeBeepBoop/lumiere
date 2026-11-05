package store

import "strings"

// PersonMatch is one person a name search found, with how many titles
// credit them.
type PersonMatch struct {
	ID, Name string
	Credits  int
	// Tag is the photo's, where FavoritePeople found one.
	Tag string
}

// SearchPeople finds people by name, most-credited first — "Hans Zimmer"
// before a crew member who shares a word with him. Guest stars are left out:
// half the person table, and almost never who someone types.
func (s *Store) SearchPeople(term string, limit int) ([]PersonMatch, error) {
	term = strings.TrimSpace(term)
	if len(term) < 2 {
		return nil, nil
	}
	rows, err := s.DB.Query(`
		SELECT person_id, name, count(DISTINCT item_id) AS n FROM person
		WHERE name LIKE ? AND COALESCE(type, '') <> 'GuestStar'
		GROUP BY person_id ORDER BY n DESC, name LIMIT ?`, "%"+term+"%", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PersonMatch
	for rows.Next() {
		var p PersonMatch
		if rows.Scan(&p.ID, &p.Name, &p.Credits) == nil {
			out = append(out, p)
		}
	}
	return out, rows.Err()
}

// FavoritePeople is the cast and crew starred from their pages, most
// credited first, each with their photo's tag where there is one — the
// Favourites page's Cast & Crew row.
func (s *Store) FavoritePeople() ([]PersonMatch, error) {
	rows, err := s.DB.Query(`
		SELECT p.person_id, MIN(p.name), count(DISTINCT p.item_id) AS n,
		       COALESCE((SELECT tag FROM image m WHERE m.item_id = p.person_id AND m.kind = 'Primary' LIMIT 1), '')
		FROM person p JOIN user_data u ON u.item_id = p.person_id AND u.is_favorite = 1
		GROUP BY p.person_id ORDER BY n DESC, MIN(p.name)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PersonMatch
	for rows.Next() {
		var p PersonMatch
		if rows.Scan(&p.ID, &p.Name, &p.Credits, &p.Tag) == nil {
			out = append(out, p)
		}
	}
	return out, rows.Err()
}
