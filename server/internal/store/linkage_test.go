package store

import "testing"

func TestLinkEpisodesDerivesWhatJellyfinHasNotWritten(t *testing.T) {
	s := testStore(t)
	// A freshly scanned show: parentage intact, series and season ids absent.
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES ('show', 'Series', 'Gallery Fake');
		INSERT INTO item (id, type, name, parent_id)
		VALUES ('s1', 'Season', 'Season 1', 'show'),
		       ('e1', 'Episode', 'One', 's1'),
		       ('e2', 'Episode', 'Two', 's1'),
		       ('e3', 'Episode', 'Filed under the show', 'show')`); err != nil {
		t.Fatal(err)
	}

	if err := LinkEpisodes(s.DB); err != nil {
		t.Fatal(err)
	}

	for _, id := range []string{"e1", "e2", "e3"} {
		var series, name string
		if err := s.DB.QueryRow(
			`SELECT COALESCE(series_id,''), COALESCE(series_name,'') FROM item WHERE id = ?`, id,
		).Scan(&series, &name); err != nil {
			t.Fatal(err)
		}
		if series != "show" {
			t.Errorf("%s series_id = %q, want show", id, series)
		}
		if name != "Gallery Fake" {
			t.Errorf("%s series_name = %q, want the show's name", id, name)
		}
	}

	// The season link too, since Latest and the season lists both read it.
	var season string
	s.DB.QueryRow(`SELECT COALESCE(season_id,'') FROM item WHERE id='e1'`).Scan(&season)
	if season != "s1" {
		t.Errorf("season_id = %q, want s1", season)
	}
	// A season learns its own series.
	var seasonSeries string
	s.DB.QueryRow(`SELECT COALESCE(series_id,'') FROM item WHERE id='s1'`).Scan(&seasonSeries)
	if seasonSeries != "show" {
		t.Errorf("season series_id = %q, want show", seasonSeries)
	}
}

func TestLinkEpisodesNeverOverwritesJellyfin(t *testing.T) {
	s := testStore(t)
	// Jellyfin says this episode belongs to another show — a cross-linked
	// special, which is a real thing. Deriving from the parent would move it.
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES
		       ('show', 'Series', 'A'), ('other', 'Series', 'B');
		INSERT INTO item (id, type, name, parent_id) VALUES ('s1', 'Season', 'S1', 'show');
		INSERT INTO item (id, type, name, parent_id, series_id, series_name)
		VALUES ('e1', 'Episode', 'One', 's1', 'other', 'B')`); err != nil {
		t.Fatal(err)
	}

	if err := LinkEpisodes(s.DB); err != nil {
		t.Fatal(err)
	}

	var series, name string
	s.DB.QueryRow(`SELECT series_id, series_name FROM item WHERE id='e1'`).Scan(&series, &name)
	if series != "other" || name != "B" {
		t.Errorf("series = %q/%q, want the stated other/B", series, name)
	}
}
