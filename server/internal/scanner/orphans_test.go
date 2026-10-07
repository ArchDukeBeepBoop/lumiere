package scanner

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestFilesWithNoLibraryJoinOneOrGo(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	root := t.TempDir()
	here := filepath.Join(root, "Show", "Extras", "NCOP.mkv")
	os.MkdirAll(filepath.Dir(here), 0o755)
	os.WriteFile(here, []byte("x"), 0o644)
	gone := filepath.Join(root, "Show", "Extras", "Old NCED.mkv")
	unmounted := "/Volumes/Not Plugged In/Show/a.mkv"
	for id, path := range map[string]string{"here": here, "gone": gone, "away": unmounted} {
		s.DB.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES (?, 'Video', ?, ?, 0)`, id, id, path)
	}
	roots := []Root{{LibraryID: "lib", Path: root, Name: "Anime"},
		{LibraryID: "away", Path: "/Volumes/Not Plugged In", Name: "Away"}}

	joined, removed := AdoptOrphanFiles(s, roots, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if joined != 1 || removed != 1 {
		t.Fatalf("joined %d, removed %d", joined, removed)
	}
	var lib string
	s.DB.QueryRow(`SELECT COALESCE(library_id, '') FROM item WHERE id = 'here'`).Scan(&lib)
	if lib != "lib" {
		t.Errorf("a file on disk joins its library, got %q", lib)
	}
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE id = 'gone'`).Scan(&n)
	if n != 0 {
		t.Error("a gone file should be in Removed Items")
	}
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE id = 'away'`).Scan(&n)
	if n != 1 {
		t.Error("a file on a drive that is not mounted is left alone")
	}
}
