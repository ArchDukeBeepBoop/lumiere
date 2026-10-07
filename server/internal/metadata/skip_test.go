package metadata

import (
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

// A library the app asked to keep off the movie database is not queued.
func TestSkippedLibrariesAreNotLookedUp(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, collection_type) VALUES ('v1', 'CollectionFolder', 'Shows', 1, 'tvshows'), ('v2', 'CollectionFolder', 'Private', 1, 'tvshows')`,
		`INSERT INTO library_folder (view_id, folder_id) VALUES ('v1', 'f1'), ('v2', 'f2')`,
		`INSERT INTO item (id, type, name, is_folder, library_id) VALUES ('a', 'Series', 'A', 1, 'f1'), ('b', 'Series', 'B', 1, 'f2')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	count := func() int {
		var n int
		s.DB.QueryRow(`SELECT count(*) FROM item WHERE ` + PendingClause).Scan(&n)
		return n
	}
	if n := count(); n != 2 {
		t.Fatalf("both pending before, got %d", n)
	}
	s.SetMeta(store.MetaLookupSkipped, "v2")
	if n := count(); n != 1 {
		t.Fatalf("the skipped library should drop out, got %d pending", n)
	}
}
