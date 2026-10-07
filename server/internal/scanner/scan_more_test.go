package scanner

import (
	"testing"
)

// Split from scan_test.go for the 300-line rule.

func TestMissingCountsOnlyFilesThisScannerWouldFind(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t, "Show/Season 1/Show - 1x01.mkv")

	// The rows an unfiltered count treated as deleted files on a first run: a
	// series carries the path of its *folder*, and a walk never yields a
	// folder. Music is the same in reverse — 3,828 tracks this scanner does not
	// handle, all reported gone.
	if _, err := s.Store.DB.Exec(`
		INSERT INTO item (id, type, name, library_id, path) VALUES
			('folder', 'Series', 'Show',  'lib', '/media/Show'),
			('track',  'Audio',  'A song','lib', '/media/Music/song.flac'),
			('gone',   'Episode','Gone',  'lib', '/media/Show/gone.mkv')`); err != nil {
		t.Fatal(err)
	}

	result, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	// Only the deleted .mkv. The folder and the track are not files this
	// scanner looks for, so their absence says nothing.
	if result.Missing != 1 {
		t.Errorf("missing = %d, want 1", result.Missing)
	}
}

func TestScanFilesLooseVideosUnderTheirFolders(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t,
		"TV/Skyline/Red Compilation.mp4",
		"TV/Skyline/Blue Compilation.mp4",
		"Clips/LoL/League Compilation.mp4",
	)
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}

	// Every file has the folder it sits in as its parent, and every folder
	// has the one above it, up to the library.
	var parentName, grandparent string
	err := s.Store.DB.QueryRow(`
		SELECT p.name, COALESCE(g.name, gp.parent_id) FROM item f
		JOIN item p ON p.id = f.parent_id
		LEFT JOIN item g ON g.id = p.parent_id
		LEFT JOIN item gp ON gp.id = p.id
		WHERE f.path LIKE '%Red Compilation.mp4'`).Scan(&parentName, &grandparent)
	if err != nil {
		t.Fatal(err)
	}
	if parentName != "Skyline" || grandparent != "TV" {
		t.Errorf("Red sits under %q / %q, want Skyline / TV", parentName, grandparent)
	}
	var folders int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Folder'`).Scan(&folders)
	if folders != 4 {
		t.Errorf("folders = %d, want 4 (TV, Skyline, Games, LoL)", folders)
	}
	// The TV folder's parent is the library itself.
	var top string
	s.Store.DB.QueryRow(`SELECT parent_id FROM item WHERE type='Folder' AND name='TV'`).Scan(&top)
	if top != "lib" {
		t.Errorf("TV's parent = %q, want the library", top)
	}
}

func TestScanFilmsInAGenreFolderAreNamedByFile(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t,
		"DC/Superman (1978).mkv",
		"DC/Injustice (2021).mkv",
		"Blade Runner (1982)/Blade Runner (1982).mkv",
	)
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	var names []string
	rows, _ := s.Store.DB.Query(`SELECT name FROM item WHERE type='Movie' ORDER BY name`)
	for rows.Next() {
		var n string
		rows.Scan(&n)
		names = append(names, n)
	}
	rows.Close()
	want := []string{"Blade Runner", "Injustice", "Superman"}
	if len(names) != 3 || names[0] != want[0] || names[1] != want[1] || names[2] != want[2] {
		t.Errorf("films = %v, want %v — two films in one folder must not both be called DC", names, want)
	}
	// Blade Runner's own folder is the film, not a Folder row; DC is one.
	var folders int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Folder'`).Scan(&folders)
	if folders != 1 {
		t.Errorf("folders = %d, want 1 (DC)", folders)
	}
}

func TestOneVideoInATelevisionFolderIsAShow(t *testing.T) {
	s := testScanner(t)
	// Declared as shows: a view of type tvshows over this folder.
	for _, q := range []string{
		`INSERT INTO item (id, type, name, collection_type, is_folder) VALUES ('view', 'CollectionFolder', 'Adult', 'tvshows', 1)`,
		`INSERT INTO item (id, type, name, is_folder) VALUES ('lib', 'Folder', 'Adult', 1)`,
		`INSERT INTO library_folder (view_id, folder_id) VALUES ('view', 'lib')`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	root := makeTree(t, "Hoshi no Uta/Hoshi no Uta.mp4")
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	var kind, seriesName string
	err := s.Store.DB.QueryRow(`
		SELECT e.type, sr.name FROM item e JOIN item sr ON sr.id = e.series_id
		WHERE e.path LIKE '%Hoshi no Uta.mp4'`).Scan(&kind, &seriesName)
	if err != nil {
		t.Fatalf("no episode row with a series: %v", err)
	}
	if kind != "Episode" || seriesName != "Hoshi no Uta" {
		t.Errorf("got %s of %q, want an Episode of Hoshi no Uta", kind, seriesName)
	}
	var films int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Movie'`).Scan(&films)
	if films != 0 {
		t.Errorf("a one-video folder in a television library became a film")
	}
}

func TestOneVideoInAPlainFolderStaysInItsFolder(t *testing.T) {
	s := testScanner(t)
	// Declared as nothing in particular: a view with no collection type.
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('view', 'CollectionFolder', 'My Videos', 1)`,
		`INSERT INTO item (id, type, name, is_folder) VALUES ('lib', 'Folder', 'My Videos', 1)`,
		`INSERT INTO library_folder (view_id, folder_id) VALUES ('view', 'lib')`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	root := makeTree(t, "Garden/Garden Party Clip.mkv")
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	var kind, name, folder string
	err := s.Store.DB.QueryRow(`
		SELECT v.type, v.name, p.name FROM item v JOIN item p ON p.id = v.parent_id
		WHERE v.path LIKE '%Garden Party Clip.mkv'`).Scan(&kind, &name, &folder)
	if err != nil {
		t.Fatalf("no video row with a folder: %v", err)
	}
	if kind != "Video" || name != "Garden Party Clip" || folder != "Garden" {
		t.Errorf("got %s %q under %q, want a Video 'Garden Party Clip' under the Garden folder", kind, name, folder)
	}
	var films int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Movie'`).Scan(&films)
	if films != 0 {
		t.Errorf("a one-video folder in a plain folder library became a film")
	}
}

func TestRepairUnfoldsFilmsInPlainFolderLibraries(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t, "Clips/clip-4.mp4", "Clips/clip-1.mp4")
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('view', 'CollectionFolder', 'My Videos', 1)`,
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('lib', 'Folder', 'My Videos', 1, '` + root + `')`,
		`INSERT INTO library_folder (view_id, folder_id) VALUES ('view', 'lib')`,
		// What the film rule wrote: two films both called Clips, at the root.
		`INSERT INTO item (id, type, name, library_id, parent_id, path, is_folder) VALUES ('f1', 'Movie', 'Clips', 'lib', 'lib', '` + root + `/Clips/clip-4.mp4', 0)`,
		`INSERT INTO item (id, type, name, library_id, parent_id, path, is_folder) VALUES ('f2', 'Movie', 'Clips', 'lib', 'lib', '` + root + `/Clips/clip-1.mp4', 0)`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := UnfoldFolderFilms(s.Store.DB, []Root{{LibraryID: "lib", Path: root}}, s.Log)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("unfolded %d, want 2", n)
	}
	var names []string
	rows, _ := s.Store.DB.Query(`
		SELECT v.name FROM item v JOIN item p ON p.id = v.parent_id
		WHERE v.type = 'Video' AND p.type = 'Folder' AND p.name = 'Clips' ORDER BY v.name`)
	for rows.Next() {
		var n string
		rows.Scan(&n)
		names = append(names, n)
	}
	rows.Close()
	if len(names) != 2 || names[0] != "clip-1" || names[1] != "clip-4" {
		t.Errorf("videos under Clips = %v, want the two files by name", names)
	}
}
