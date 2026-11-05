package store

import "testing"

func TestContainersBorrowTheirFirstChildsPicture(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, collection_type, is_folder) VALUES
			('v3d', 'CollectionFolder', '3D', NULL, 1), ('vtv', 'CollectionFolder', 'TV Shows', 'tvshows', 1)`,
		`INSERT INTO library_folder (view_id, folder_id) VALUES ('v3d', 'f3d'), ('vtv', 'ftv')`,
		`INSERT INTO item (id, type, name, sort_name, parent_id, library_id, is_folder) VALUES
			('outer', 'Folder', 'Trips', 'Trips', 'f3d', 'f3d', 1),
			('inner', 'Folder', 'Alps', 'Alps', 'outer', 'f3d', 1),
			('b', 'Video', 'B clip', 'B clip', 'inner', 'f3d', 0),
			('a', 'Video', 'A clip', 'A clip', 'inner', 'f3d', 0),
			('home', 'Series', 'Holidays', 'Holidays', 'f3d', 'f3d', 1),
			('s1', 'Season', 'Season 1', 'Season 1', 'home', 'f3d', 1),
			('e1', 'Episode', 'Day one', 'Day one', 's1', 'f3d', 0),
			('show', 'Series', 'A Show', 'A Show', 'ftv', 'ftv', 1),
			('ss1', 'Season', 'Season 1', 'Season 1', 'show', 'ftv', 1),
			('se1', 'Episode', 'Pilot', 'Pilot', 'ss1', 'ftv', 0),
			('posted', 'Folder', 'Has one', 'Has one', 'f3d', 'f3d', 1),
			('c', 'Video', 'C clip', 'C clip', 'posted', 'f3d', 0)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES
			('a', 'Primary', 0, '/frames/a.jpg', 'ta'), ('b', 'Primary', 0, '/frames/b.jpg', 'tb'),
			('e1', 'Primary', 0, '/frames/e1.jpg', 'te'), ('se1', 'Primary', 0, '/frames/se1.jpg', 'ts'),
			('c', 'Primary', 0, '/frames/c.jpg', 'tc'), ('posted', 'Primary', 0, '/chosen.jpg', 'mine')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.InheritContainerArt(); err != nil {
		t.Fatal(err)
	}
	pic := func(id string) string {
		var p string
		s.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = 'Primary'`, id).Scan(&p)
		return p
	}
	if pic("inner") != "/frames/a.jpg" || pic("outer") != "/frames/a.jpg" {
		t.Fatalf("folders: inner %q outer %q", pic("inner"), pic("outer"))
	}
	if pic("s1") != "/frames/e1.jpg" || pic("home") != "/frames/e1.jpg" {
		t.Fatalf("a folder library's show: %q %q", pic("home"), pic("s1"))
	}
	if pic("show") != "" || pic("ss1") != "" {
		t.Fatal("a TV library's show keeps to its own art")
	}
	if pic("posted") != "/chosen.jpg" {
		t.Fatal("a chosen picture stays")
	}
	// The source goes; the borrowed copies go with it, and the next one is borrowed.
	s.DB.Exec(`DELETE FROM image WHERE item_id = 'a'`)
	s.InheritContainerArt()
	if pic("inner") != "/frames/b.jpg" || pic("outer") != "/frames/b.jpg" {
		t.Fatalf("after the source went: %q %q", pic("inner"), pic("outer"))
	}
}
