package metadata

import (
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

// "Identify everything" reaches a title that looks finished — synopsis and
// poster, no provider id — which the ordinary pass leaves alone; neither
// touches one already matched, and both respect a skipped library.
func TestUnmatchedReachesWhatPendingLeaves(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, collection_type) VALUES ('v1', 'CollectionFolder', 'Films', 1, 'movies'), ('v2', 'CollectionFolder', 'Kept', 1, 'movies')`,
		`INSERT INTO library_folder (view_id, folder_id) VALUES ('v1', 'f1'), ('v2', 'f2')`,
		`INSERT INTO item (id, type, name, is_folder, library_id, overview) VALUES
			('bare', 'Movie', 'Bare', 0, 'f1', ''),
			('looks-done', 'Movie', 'Looks Done', 0, 'f1', 'A synopsis.'),
			('matched', 'Movie', 'Matched', 0, 'f1', ''),
			('skipped', 'Movie', 'Skipped', 0, 'f2', '')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('looks-done', 'Primary', 0, '/p.jpg', 't')`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('matched', 'provider:Tmdb', '1')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	s.SetMeta(store.MetaLookupSkipped, "v2")
	e := &Enricher{Store: s}
	ids := func(items []Pending, err error) map[string]bool {
		if err != nil {
			t.Fatal(err)
		}
		out := map[string]bool{}
		for _, i := range items {
			out[i.ID] = true
		}
		return out
	}
	pending := ids(e.PendingItems(100))
	unmatched := ids(e.UnmatchedItems(100))
	if !pending["bare"] || pending["looks-done"] || pending["matched"] || pending["skipped"] {
		t.Fatalf("pending = %v", pending)
	}
	if !unmatched["bare"] || !unmatched["looks-done"] || unmatched["matched"] || unmatched["skipped"] {
		t.Fatalf("unmatched = %v", unmatched)
	}
}
