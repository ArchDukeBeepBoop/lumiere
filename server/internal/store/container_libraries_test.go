package store

import (
	"path/filepath"
	"testing"
)

// A library with collections but no Collections library gets one, under the
// id an earlier library used, and every stray collection is filed into it;
// a second start changes nothing.
func TestContainerLibrariesAreEnsured(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('c1', 'BoxSet', 'Vampires', 1), ('c2', 'BoxSet', 'Heists', 1)`)
	s.SetMeta("boxsets_view_id", "oldview")
	n, err := s.EnsureContainerLibraries()
	if err != nil || n != 2 {
		t.Fatalf("homed %d, err %v", n, err)
	}
	var view, kind string
	s.DB.QueryRow(`SELECT id, collection_type FROM item WHERE type = 'CollectionFolder' AND name = 'Collections'`).Scan(&view, &kind)
	if view != "oldview" || kind != "boxsets" {
		t.Fatalf("view %q kind %q", view, kind)
	}
	var homeless int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE type = 'BoxSet' AND parent_id IS NULL`).Scan(&homeless)
	if homeless != 0 {
		t.Fatalf("%d collections left unfiled", homeless)
	}
	libs, _ := s.ListLibraries()
	for _, l := range libs {
		if l.Kind == "boxsets" && len(l.Folders) != 0 {
			t.Fatalf("the placeholder folder must not show as a place on disk: %v", l.Folders)
		}
	}
	if again, _ := s.EnsureContainerLibraries(); again != 0 {
		t.Fatalf("second start filed %d", again)
	}
}
