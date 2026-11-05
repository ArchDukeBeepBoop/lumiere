package store

import (
	"path/filepath"
	"reflect"
	"testing"
)

func smartFixture(t *testing.T) *Store {
	s, err := Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, production_year, community_rating, runtime_ticks, library_id) VALUES
			('spirited', 'Movie', 'Spirited Away', 0, 2001, 8.5, 75000000000, 'f1'),
			('parasite', 'Movie', 'Parasite', 0, 2019, 8.5, 79800000000, 'f1'),
			('akira', 'Movie', 'Akira', 0, 1988, 7.9, 74400000000, 'f1'),
			('secret', 'Movie', 'Secret', 0, 2001, 9.0, 60000000000, 'fp')`,
		`INSERT INTO item_value (item_id, kind, value) VALUES
			('spirited', 'country', 'JP'), ('akira', 'country', 'JP'), ('parasite', 'country', 'KR'),
			('secret', 'country', 'JP'), ('akira', 'genre', 'Science Fiction')`,
		`INSERT INTO user_data (item_id, played, updated_at) VALUES ('spirited', 1, '2026-10-25T00:00:00Z')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func TestSmartRulesMatch(t *testing.T) {
	s := smartFixture(t)
	run := func(r SmartRules) []string {
		got, err := s.SmartMembers(r, []string{"fp"})
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	japan := SmartRule{Field: "country", Op: "is", Value: "JP"}
	if got := run(SmartRules{Rules: []SmartRule{japan}}); !reflect.DeepEqual(got, []string{"spirited", "akira"}) {
		t.Fatalf("Japanese films, best first, private left out: %v", got)
	}
	unwatched := SmartRule{Field: "watched", Op: "is", Value: "false"}
	if got := run(SmartRules{Rules: []SmartRule{japan, unwatched}}); !reflect.DeepEqual(got, []string{"akira"}) {
		t.Fatalf("unwatched Japanese: %v", got)
	}
	short := SmartRule{Field: "runtime", Op: "≤", Value: "125"}
	rated := SmartRule{Field: "rating", Op: "≥", Value: "8.5"}
	if got := run(SmartRules{Rules: []SmartRule{short, rated}, Sort: "year"}); !reflect.DeepEqual(got, []string{"spirited"}) {
		t.Fatalf("short and highly rated: %v", got)
	}
	scifi := SmartRule{Field: "genre", Op: "is", Value: "science fiction"}
	korea := SmartRule{Field: "country", Op: "is", Value: "KR"}
	if got := run(SmartRules{Match: "any", Rules: []SmartRule{scifi, korea}, Sort: "name"}); !reflect.DeepEqual(got, []string{"akira", "parasite"}) {
		t.Fatalf("any: %v", got)
	}
}

func TestSmartRulesRefuseUnknownFields(t *testing.T) {
	s := smartFixture(t)
	for _, r := range []SmartRule{
		{Field: "name; DROP TABLE item", Op: "is", Value: "x"},
		{Field: "year", Op: "LIKE", Value: "1"},
		{Field: "type", Op: "is", Value: "Episode"},
	} {
		if _, err := s.SmartMembers(SmartRules{Rules: []SmartRule{r}}, nil); err == nil {
			t.Fatalf("%v should be refused", r)
		}
	}
}
