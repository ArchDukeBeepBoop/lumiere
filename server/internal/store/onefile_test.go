package store

import "testing"

func TestASecondRowForAFileIsRefused(t *testing.T) {
	s := testStore(t)
	if err := onePerFile(s.DB); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DB.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES ('a', 'Episode', 'Ep', '/m/x.mkv', 0)`); err != nil {
		t.Fatal(err)
	}
	// What the importer and the scanner both now say.
	if _, err := s.DB.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES ('b', 'Episode', 'Ep', '/m/x.mkv', 0) ON CONFLICT DO NOTHING`); err != nil {
		t.Fatal(err)
	}
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE path = '/m/x.mkv'`).Scan(&n)
	if n != 1 {
		t.Errorf("%d rows for one file, want 1", n)
	}
	// Folders may share a path with a file row's parent — untouched.
	if _, err := s.DB.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES ('f1', 'Series', 'S', '/m', 1), ('f2', 'Folder', 'S', '/m', 1)`); err != nil {
		t.Errorf("folders sharing a path were refused: %v", err)
	}
}

func TestExistingTwinsAreFoldedBeforeTheRuleArrives(t *testing.T) {
	s := legacyStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('a', 'Episode', 'Ep', '/m/y.mkv', 0)`,
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('b', 'Episode', 'Ep', '/m/y.mkv', 0)`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if err := onePerFile(s.DB); err != nil {
		t.Fatal(err)
	}
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE path = '/m/y.mkv'`).Scan(&n)
	if n != 1 {
		t.Errorf("%d rows, want the twins folded to 1", n)
	}
}
