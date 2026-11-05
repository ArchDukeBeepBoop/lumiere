package store

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// Smart collections: rules, not a list. "Japanese films rated 8 or more",
// "unwatched sci-fi under 100 minutes", "added this month" — kept current
// by re-reading the rules whenever the library changes, the way Kometa's
// smart builders and Apple Music's smart playlists work. A smart collection
// is an ordinary collection carrying its rules as `smart:rules`; its members
// are whatever the rules match now.

// SmartRules is a collection's rules.
type SmartRules struct {
	Match string      `json:"Match"` // "all" (default) or "any"
	Rules []SmartRule `json:"Rules"`
	Sort  string      `json:"Sort,omitempty"` // rating, year, added, name
	Limit int         `json:"Limit,omitempty"`
}

// SmartRule is one condition.
type SmartRule struct {
	Field string `json:"Field"`
	Op    string `json:"Op"`
	Value string `json:"Value"`
}

// SmartFields are the fields a rule may name, with their operators. The
// allowlist is the whole defence: a field or operator not here is refused,
// so a request string never reaches the SQL text.
var SmartFields = map[string][]string{
	"genre": {"is", "is not"}, "keyword": {"is", "is not"}, "country": {"is", "is not"},
	"studio": {"is", "is not"}, "library": {"is", "is not"}, "type": {"is"},
	"year": {"≥", "≤"}, "rating": {"≥", "≤"}, "runtime": {"≥", "≤"},
	"added": {"within days"}, "watched": {"is"}, "favourite": {"is"}, "name": {"contains"},
}

// clause turns one rule into SQL over `i` with its arguments.
func (r SmartRule) clause() (string, []any, error) {
	ops, ok := SmartFields[r.Field]
	if !ok || !contains(ops, r.Op) {
		return "", nil, fmt.Errorf("unknown rule %s %s", r.Field, r.Op)
	}
	not := r.Op == "is not"
	value := strings.TrimSpace(r.Value)
	number := func() (float64, error) { return strconv.ParseFloat(value, 64) }
	compare := map[string]string{"≥": ">=", "≤": "<="}[r.Op]
	switch r.Field {
	case "genre", "keyword", "country", "studio":
		kind := map[string]string{"genre": "genre", "keyword": "tag", "country": "country", "studio": "studio"}[r.Field]
		sql := `EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id AND v.kind = ? AND v.value = ? COLLATE NOCASE)`
		if not {
			sql = "NOT " + sql
		}
		return sql, []any{kind, value}, nil
	case "library":
		sql := `i.library_id IN (SELECT folder_id FROM library_folder WHERE view_id = ?)`
		if not {
			sql = "NOT (" + sql + ")"
		}
		return sql, []any{value}, nil
	case "type":
		if value != "Movie" && value != "Series" {
			return "", nil, fmt.Errorf("type is Movie or Series")
		}
		return `i.type = ?`, []any{value}, nil
	case "year", "rating":
		n, err := number()
		if err != nil {
			return "", nil, err
		}
		column := map[string]string{"year": "i.production_year", "rating": "i.community_rating"}[r.Field]
		return column + " " + compare + " ?", []any{n}, nil
	case "runtime":
		n, err := number()
		if err != nil {
			return "", nil, err
		}
		return "i.runtime_ticks " + compare + " ?", []any{int64(n * 60 * 10_000_000)}, nil
	case "added":
		n, err := number()
		if err != nil {
			return "", nil, err
		}
		return `i.date_created >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', ?)`, []any{fmt.Sprintf("-%d days", int(n))}, nil
	case "watched", "favourite":
		want := value == "true" || value == "yes"
		column := map[string]string{"watched": "u.played", "favourite": "u.is_favorite"}[r.Field]
		sql := `COALESCE((SELECT ` + column + ` FROM user_data u WHERE u.item_id = i.id), 0) = ?`
		if r.Field == "watched" {
			// A show is watched when none of its episodes is left.
			sql = `(CASE WHEN i.type = 'Series' THEN NOT EXISTS (SELECT 1 FROM item e WHERE e.series_id = i.id
				AND e.type = 'Episode' AND COALESCE((SELECT u.played FROM user_data u WHERE u.item_id = e.id), 0) = 0)
				ELSE COALESCE((SELECT u.played FROM user_data u WHERE u.item_id = i.id), 0) = 1 END) = ?`
		}
		return sql, []any{boolInt(want)}, nil
	case "name":
		return `i.name LIKE ? ESCAPE '\'`, []any{"%" + likeEscape(value) + "%"}, nil
	}
	return "", nil, fmt.Errorf("unknown field %s", r.Field)
}

// SmartMembers runs the rules: the matching films and shows, best first.
// Private libraries are left out unless a rule names one.
func (s *Store) SmartMembers(rules SmartRules, privateFolders []string) ([]string, error) {
	if len(rules.Rules) == 0 {
		return nil, fmt.Errorf("a smart collection needs a rule")
	}
	var parts []string
	var args []any
	namesLibrary := false
	for _, r := range rules.Rules {
		sql, a, err := r.clause()
		if err != nil {
			return nil, err
		}
		if r.Field == "library" && r.Op == "is" {
			namesLibrary = true
		}
		parts = append(parts, "("+sql+")")
		args = append(args, a...)
	}
	join := " AND "
	if rules.Match == "any" {
		join = " OR "
	}
	where := `i.type IN ('Movie', 'Series') AND i.extra_type IS NULL AND (` + strings.Join(parts, join) + `)`
	if !namesLibrary && len(privateFolders) > 0 {
		where += ` AND COALESCE(i.library_id, '') NOT IN (?` + strings.Repeat(",?", len(privateFolders)-1) + `)`
		for _, f := range privateFolders {
			args = append(args, f)
		}
	}
	order := map[string]string{
		"rating": "i.community_rating DESC", "year": "i.production_year DESC",
		"added": "i.date_created DESC", "name": "COALESCE(i.sort_name, i.name) COLLATE NOCASE",
	}[rules.Sort]
	if order == "" {
		order = "i.community_rating DESC"
	}
	limit := rules.Limit
	if limit <= 0 || limit > 500 {
		limit = 500
	}
	rows, err := s.DB.Query(`SELECT i.id FROM item i WHERE `+where+` ORDER BY `+order+` LIMIT ?`, append(args, limit)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		out = append(out, id)
	}
	return out, rows.Err()
}

// SmartCollections lists every smart collection with its rules.
func (s *Store) SmartCollections() map[string]SmartRules {
	rows, err := s.DB.Query(`SELECT v.item_id, v.value FROM item_value v JOIN item b ON b.id = v.item_id
		WHERE v.kind = 'smart:rules' AND b.type = 'BoxSet'`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := map[string]SmartRules{}
	for rows.Next() {
		var id, raw string
		rows.Scan(&id, &raw)
		var r SmartRules
		if json.Unmarshal([]byte(raw), &r) == nil {
			out[id] = r
		}
	}
	return out
}
