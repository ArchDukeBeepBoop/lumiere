package store

import "testing"

func TestApplyIdentification(t *testing.T) {
	s := openTempStore(t)
	if _, err := s.DB.Exec(
		`INSERT INTO item (id, type, name, sort_name, production_year)
		 VALUES ('i1','Movie','Movie.2019.1080p.WEB','Movie.2019.1080p.WEB', 1998)`,
	); err != nil {
		t.Fatal(err)
	}

	year := 2019
	if err := s.ApplyIdentification("i1", Identification{
		Name:        "The Real Title",
		Year:        &year,
		ProviderIDs: map[string]string{"Tmdb": "12345", "Imdb": "tt999", "": "skipped"},
	}); err != nil {
		t.Fatal(err)
	}

	var name, sortName string
	var got int
	if err := s.DB.QueryRow(
		`SELECT name, sort_name, production_year FROM item WHERE id='i1'`,
	).Scan(&name, &sortName, &got); err != nil {
		t.Fatal(err)
	}
	if name != "The Real Title" {
		t.Errorf("name = %q", name)
	}
	if sortName != "The Real Title" {
		t.Errorf("sort_name = %q — a corrected title filed under the old letter", sortName)
	}
	if got != year {
		t.Errorf("production_year = %d, want %d", got, year)
	}

	ids := map[string]string{}
	rows, err := s.DB.Query(
		`SELECT kind, value FROM item_value WHERE item_id='i1' AND kind LIKE 'provider:%'`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			t.Fatal(err)
		}
		ids[k] = v
	}
	if ids["provider:Tmdb"] != "12345" || ids["provider:Imdb"] != "tt999" {
		t.Errorf("provider ids = %v", ids)
	}
	if len(ids) != 2 {
		t.Errorf("an empty provider key was stored: %v", ids)
	}

	// Identifying again replaces rather than merges: what was there was wrong.
	if err := s.ApplyIdentification("i1", Identification{
		Name:        "Corrected Again",
		ProviderIDs: map[string]string{"Tmdb": "999"},
	}); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := s.DB.QueryRow(
		`SELECT count(*) FROM item_value WHERE item_id='i1' AND kind LIKE 'provider:%'`,
	).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Errorf("provider ids after re-identifying = %d, want 1", n)
	}

	if err := s.ApplyIdentification("missing", Identification{Name: "x"}); err != ErrNoItem {
		t.Errorf("identifying an unknown item = %v, want ErrNoItem", err)
	}
}
