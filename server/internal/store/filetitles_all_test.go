package store

import "testing"

func TestFileTitlesApplyAndUndo(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('e', 'Episode', 'Dark - 3x01 - Deja-vu', 0)`)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('k', 'Episode', 'Show - 1x02 - Kept', 0)`)
	s.SetItemValue("k", "lock:name", "1")
	if n, err := s.TitleAllFromFilenames(); err != nil || n != 1 {
		t.Fatalf("renamed %d (%v), want 1", n, err)
	}
	var name string
	s.DB.QueryRow(`SELECT name FROM item WHERE id = 'e'`).Scan(&name)
	if name != "Deja-vu" {
		t.Fatalf("got %q", name)
	}
	if n, _ := s.UndoFileTitles(); n != 1 {
		t.Fatalf("restored %d", n)
	}
	s.DB.QueryRow(`SELECT name FROM item WHERE id = 'e'`).Scan(&name)
	if name != "Dark - 3x01 - Deja-vu" {
		t.Fatalf("undo gave %q", name)
	}
}
