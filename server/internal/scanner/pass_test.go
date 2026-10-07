package scanner

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAPassFollowsAFileMovedBetweenLibraries(t *testing.T) {
	s := testScanner(t)
	from := makeTree(t, "Clips/Holiday.mp4")
	to := makeTree(t)
	if _, err := s.ScanLibrary("a", from, nil); err != nil {
		t.Fatal(err)
	}
	var oldID string
	s.Store.DB.QueryRow(`SELECT id FROM item WHERE path LIKE '%Holiday.mp4'`).Scan(&oldID)
	if _, err := s.Store.DB.Exec(
		`INSERT INTO image (item_id, kind, path, tag) VALUES (?, 'Primary', '/art/holiday.jpg', 't')`, oldID,
	); err != nil {
		t.Fatal(err)
	}

	// Dragged from one library's folder into another's.
	if err := os.MkdirAll(filepath.Join(to, "Favourites"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(from, "Clips", "Holiday.mp4"), filepath.Join(to, "Favourites", "Holiday.mp4")); err != nil {
		t.Fatal(err)
	}

	// The emptied library is read first, so at that moment the file is simply
	// gone; only the pass, at its end, can see where it went.
	s.BeginPass()
	if _, err := s.ScanLibrary("a", from, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ScanLibrary("b", to, nil); err != nil {
		t.Fatal(err)
	}
	moved, removed, _ := s.FinishPass()
	if moved != 1 || removed != 0 {
		t.Errorf("moved = %d removed = %d, want 1 and 0", moved, removed)
	}

	var id, library string
	err := s.Store.DB.QueryRow(`SELECT id, library_id FROM item WHERE path LIKE '%Favourites/Holiday.mp4'`).Scan(&id, &library)
	if err != nil {
		t.Fatal(err)
	}
	if id != oldID || library != "b" {
		t.Errorf("row is %s in %s, want the old row %s in b", id, library, oldID)
	}
	var pictures int
	s.Store.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = ?`, oldID).Scan(&pictures)
	if pictures != 1 {
		t.Error("the picture did not travel with the file")
	}
	var rows int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE path LIKE '%Holiday.mp4'`).Scan(&rows)
	if rows != 1 {
		t.Errorf("%d rows for the file, want 1", rows)
	}
}
