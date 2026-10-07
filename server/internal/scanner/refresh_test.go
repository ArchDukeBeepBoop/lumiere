package scanner

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAFileReplacedInPlaceIsReadAgain(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t, "Show/Season 1/Show - 1x01.mkv")
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	var id string
	s.Store.DB.QueryRow(`SELECT id FROM item WHERE path LIKE '%1x01.mkv'`).Scan(&id)
	// What the broken copy left: a probed stream, and a watched tick that
	// belongs to the item rather than to the file.
	for _, q := range []string{
		`INSERT INTO stream (item_id, idx, type, codec) VALUES ('` + id + `', 0, 'Video', 'garbage')`,
		`INSERT INTO user_data (item_id, played, updated_at) VALUES ('` + id + `', 1, 'x')`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}

	// A good copy under the same name, a different size.
	path := filepath.Join(root, "Show/Season 1/Show - 1x01.mkv")
	if err := os.WriteFile(path, make([]byte, 2<<20), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}

	var size int64
	var streams, played, rows int
	s.Store.DB.QueryRow(`SELECT COALESCE(size, 0) FROM item WHERE id = ?`, id).Scan(&size)
	s.Store.DB.QueryRow(`SELECT count(*) FROM stream WHERE item_id = ?`, id).Scan(&streams)
	s.Store.DB.QueryRow(`SELECT played FROM user_data WHERE item_id = ?`, id).Scan(&played)
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE path = ?`, path).Scan(&rows)
	if size != 2<<20 {
		t.Errorf("size = %d, want the new file's 2 MiB", size)
	}
	if streams != 0 {
		t.Error("the broken copy's streams survived the replacement")
	}
	if played != 1 || rows != 1 {
		t.Errorf("played = %d, rows = %d: the item itself must stay as it was", played, rows)
	}
}
