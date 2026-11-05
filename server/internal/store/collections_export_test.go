package store

import (
	"path/filepath"
	"testing"
)

// A hand-made collection written out and read into a library rebuilt with new
// ids comes back with its members, matched by TMDB id and by path; a theme is
// left to rebuild itself.
func TestCollectionsSurviveARebuild(t *testing.T) {
	old, _ := Open(filepath.Join(t.TempDir(), "old"))
	old.DB.Exec(`INSERT INTO item (id, type, name, is_folder, path) VALUES
		('m1', 'Movie', 'Iron Man', 0, '/m/Iron Man.mkv'), ('m2', 'Movie', 'Thor', 0, '/m/Thor.mkv')`)
	old.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES ('m1', 'provider:Tmdb', '1726')`)
	old.CreateContainer("BoxSet", "Marvel Cinematic Universe", []string{"m1", "m2"})
	theme, _ := old.CreateContainer("BoxSet", "Vampires", nil)
	old.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, 'theme', 'vampires')`, theme)
	dir := t.TempDir()
	path, err := old.WriteCollectionsExport(dir)
	if err != nil {
		t.Fatal(err)
	}

	rebuilt, _ := Open(filepath.Join(t.TempDir(), "new"))
	rebuilt.DB.Exec(`INSERT INTO item (id, type, name, is_folder, path) VALUES
		('n1', 'Movie', 'Iron Man', 0, '/elsewhere/IM.mkv'), ('n2', 'Movie', 'Thor', 0, '/m/Thor.mkv')`)
	rebuilt.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES ('n1', 'provider:Tmdb', '1726')`)
	made, matched, err := rebuilt.ImportCollections(path)
	if err != nil || made != 1 || matched != 2 {
		t.Fatalf("made %d matched %d err %v", made, matched, err)
	}
	var vampires int
	rebuilt.DB.QueryRow(`SELECT count(*) FROM item WHERE name = 'Vampires'`).Scan(&vampires)
	if vampires != 0 {
		t.Fatal("a theme is rebuilt by its keywords, not imported")
	}
	if again, _, _ := rebuilt.ImportCollections(path); again != 0 {
		t.Fatal("importing twice must not duplicate")
	}
}
