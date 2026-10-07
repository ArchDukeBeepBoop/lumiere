package store

import "testing"

func TestNormalizeIDRejectsTheZeroGUID(t *testing.T) {
	// Jellyfin writes this on an episode whose season it never determined. It is
	// well-formed, so every check for "is this an id" passes, and it names a row
	// that cannot exist — which is worse than an empty string, not better.
	for _, in := range []string{
		"00000000000000000000000000000000",
		"00000000-0000-0000-0000-000000000000",
	} {
		if got := NormalizeID(in); got != "" {
			t.Errorf("NormalizeID(%q) = %q, want empty", in, got)
		}
	}
	// A real id that merely starts with zeros is untouched.
	const real = "0000000000000000000000000000000a"
	if got := NormalizeID(real); got != real {
		t.Errorf("NormalizeID(%q) = %q, want it unchanged", real, got)
	}
}

func TestClearZeroIDsUnparentsWhatItShould(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, series_id, season_id, parent_id)
		VALUES ('e1', 'Episode', 'Orphan', 'show', ?, 'show'),
		       ('e2', 'Episode', 'Placed', 'show', 's1', 's1')`, ZeroGUID); err != nil {
		t.Fatal(err)
	}
	if err := clearZeroIDs(s.DB); err != nil {
		t.Fatal(err)
	}

	var seasonID *string
	if err := s.DB.QueryRow(`SELECT season_id FROM item WHERE id='e1'`).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	if seasonID != nil {
		t.Errorf("season_id = %q, want NULL", *seasonID)
	}
	// A real season id is left alone, and so is the series the orphan still
	// belongs to — losing that would move the episode out of its own show.
	var placed, series string
	s.DB.QueryRow(`SELECT season_id FROM item WHERE id='e2'`).Scan(&placed)
	s.DB.QueryRow(`SELECT series_id FROM item WHERE id='e1'`).Scan(&series)
	if placed != "s1" {
		t.Errorf("season_id = %q, want s1", placed)
	}
	if series != "show" {
		t.Errorf("series_id = %q, want show", series)
	}
}

func TestSplitArtists(t *testing.T) {
	// The separator Jellyfin uses, and the trailing one its data is full of.
	got := splitArtists("Metric|Brie Larson| |Emily Haines|")
	want := []string{"Metric", "Brie Larson", "Emily Haines"}
	if len(got) != len(want) {
		t.Fatalf("splitArtists = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("splitArtists = %v, want %v", got, want)
		}
	}
	if splitArtists("") != nil {
		t.Error("an empty column should be no artists, not one nameless one")
	}
}
