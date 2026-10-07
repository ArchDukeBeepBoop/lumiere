package store

import "strings"

// PersonMatch is one person a name search found, with how many titles
// credit them.
type PersonMatch struct {
	ID, Name string
	Credits  int
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
