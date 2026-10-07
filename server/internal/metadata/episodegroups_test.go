package metadata

import (
	"io"
	"log/slog"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestChoosingAnOrderReleasesTheShowForRenaming(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('jl', 'Series', 'Justice League', 1)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('jl', 'provider:Tmdb', '2604')`,
		`INSERT INTO item (id, type, name, series_id, parent_index_number, index_number, overview, is_folder)
		 VALUES ('e1', 'Episode', 'Kid Stuff', 'jl', 3, 3, 'From the wrong order.', 0)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('e1', 'provider:none', '')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('e1', 'Primary', 0, '/s.jpg', 't')`,
		// Typed by hand: stays exactly as it is.
		`INSERT INTO item (id, type, name, series_id, parent_index_number, index_number, overview, is_folder)
		 VALUES ('e2', 'Episode', 'My Title', 'jl', 3, 4, 'Mine.', 0)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('e2', 'lock:*', '1')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('e2', 'Primary', 0, '/m.jpg', 'm')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	e := &Enricher{Store: s, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	if err := e.SetEpisodeGroup("jl", "grp"); err != nil {
		t.Fatal(err)
	}
	if got := e.EpisodeGroup("jl"); got != "grp" {
		t.Errorf("group = %q, want grp", got)
	}
	batches, err := e.PendingEpisodeArt(10)
	if err != nil {
		t.Fatal(err)
	}
	if len(batches) != 1 || batches[0].Group != "grp" || batches[0].Episodes[3] != "e1" {
		t.Fatalf("batches = %+v, want e1 asked for under grp", batches)
	}
	if _, locked := batches[0].Episodes[4]; locked {
		t.Error("a locked episode was released")
	}
	var overview string
	s.DB.QueryRow(`SELECT COALESCE(overview, '') FROM item WHERE id = 'e2'`).Scan(&overview)
	if overview != "Mine." {
		t.Error("a locked synopsis was cleared")
	}

	// And a title under the new order replaces the one from the old.
	if err := e.nameEpisode("e1", EpisodeFacts{Name: "Kids' Stuff", Overview: "Right."}); err != nil {
		t.Fatal(err)
	}
	var name string
	s.DB.QueryRow(`SELECT name FROM item WHERE id = 'e1'`).Scan(&name)
	if name != "Kids' Stuff" {
		t.Errorf("name = %q, want the group's title", name)
	}
}

func TestALooseFileFiledAsASpecialIsNotNamedFromTMDB(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('show', 'Series', 'Oedo', 1)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('show', 'provider:Tmdb', '1')`,
		`INSERT INTO item (id, type, name, series_id, parent_index_number, index_number, is_folder)
		 VALUES ('loose', 'Episode', 'Oedo 808', 'show', 0, 808, 0)`,
		`INSERT INTO repair_log (step, item_id, created, at) VALUES ('seat', 'loose', 0, 'x')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	e := &Enricher{Store: s}
	batches, err := e.PendingEpisodeArt(10)
	if err != nil {
		t.Fatal(err)
	}
	if len(batches) != 0 {
		t.Errorf("a loose special was queued for naming: %+v", batches)
	}
}
