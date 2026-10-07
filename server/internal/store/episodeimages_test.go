package store

import "testing"

func TestEpisodesWithoutImagesSkipsTheOnesThatHaveOne(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES ('show', 'Series', 'Show');
		INSERT INTO item (id, type, name, series_id, parent_index_number, index_number)
		VALUES ('e1', 'Episode', 'One',   'show', 1, 1),
		       ('e2', 'Episode', 'Two',   'show', 1, 2),
		       ('e3', 'Episode', 'Three', 'show', 1, 3),
		       ('x1', 'Episode', 'Other', 'other', 1, 1);
		INSERT INTO item (id, type, name, series_id, parent_index_number, index_number, extra_type)
		VALUES ('ex', 'Episode', 'A trailer', 'show', 1, 4, 'Trailer');
		INSERT INTO image (item_id, kind, idx, path, tag)
		VALUES ('e2', 'Primary', 0, '/tmp/e2.jpg', 'tag')`); err != nil {
		t.Fatal(err)
	}

	got, err := s.EpisodesWithoutImages("show")
	if err != nil {
		t.Fatal(err)
	}
	// e2 has a picture already, x1 belongs to another series, and an extra is
	// not an episode anyone browses.
	if len(got) != 2 || got[0].ID != "e1" || got[1].ID != "e3" {
		t.Fatalf("got %+v, want e1 and e3", got)
	}
	if got[0].Season != 1 || got[0].Episode != 1 {
		t.Errorf("numbering = S%dE%d, want S1E1", got[0].Season, got[0].Episode)
	}
}

func TestEpisodesWithoutImagesNeedsNumbering(t *testing.T) {
	s := testStore(t)
	// A provider is asked by season and episode number. An episode carrying
	// neither cannot be looked up, so offering it would guarantee a wrong match.
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, series_id) VALUES ('e1', 'Episode', 'One', 'show')`,
	); err != nil {
		t.Fatal(err)
	}
	got, err := s.EpisodesWithoutImages("show")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Errorf("got %+v, want nothing an unnumbered episode could match", got)
	}
}

func TestProviderIDIsEmptyRatherThanAnError(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES ('show', 'Series', 'Show');
		INSERT INTO item_value (item_id, kind, value)
		VALUES ('show', 'provider:Tmdb', '12345')`); err != nil {
		t.Fatal(err)
	}

	id, err := s.ProviderID("show", "Tmdb")
	if err != nil || id != "12345" {
		t.Fatalf("ProviderID = %q, %v; want 12345", id, err)
	}
	// An unidentified series is ordinary, not a failure.
	id, err = s.ProviderID("show", "Tvdb")
	if err != nil || id != "" {
		t.Fatalf("ProviderID = %q, %v; want empty and no error", id, err)
	}
}
