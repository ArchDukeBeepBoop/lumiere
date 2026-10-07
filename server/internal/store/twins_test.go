package store

import "testing"

func TestMergeTwinsKeepsTheFirstRowAndWhatTheTwinKnew(t *testing.T) {
	s := legacyStore(t)
	const path = "/m/Show/Season 2/Show - 2x11 - Mirror.mkv"
	for _, q := range []string{
		// The scanner's row, first, named from the file and unwatched.
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('scan', 'Episode', 'Show - 2x11 - Mirror', '` + path + `', 0)`,
		// The import's twin: a real title, a watched flag, a still, a provider id.
		`INSERT INTO item (id, type, name, overview, path, is_folder) VALUES ('jf', 'Episode', 'Mirror', 'What is reflected.', '` + path + `', 0)`,
		`INSERT INTO user_data (item_id, played, updated_at) VALUES ('jf', 1, '2026-01-01')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('jf', 'Primary', 0, '/img/jf.jpg', 't1')`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('jf', 'provider:Tvdb', '123')`,
		// Something the kept row already has: its copy stays, the twin's goes.
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('scan', 'Backdrop', 0, '/img/scan-bd.jpg', 's1')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('jf', 'Backdrop', 0, '/img/jf-bd.jpg', 'j1')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}

	n, err := s.MergeTwins()
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Errorf("merged %d, want 1", n)
	}

	var rows int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE path = ?`, path).Scan(&rows)
	if rows != 1 {
		t.Fatalf("%d rows for the path, want 1", rows)
	}
	var id, name, overview string
	s.DB.QueryRow(`SELECT id, name, COALESCE(overview, '') FROM item WHERE path = ?`, path).Scan(&id, &name, &overview)
	if id != "scan" {
		t.Errorf("kept %q, want the scanner's row", id)
	}
	if name != "Mirror" || overview != "What is reflected." {
		t.Errorf("kept row is named %q / %q, want the twin's title", name, overview)
	}
	var played int
	s.DB.QueryRow(`SELECT played FROM user_data WHERE item_id = 'scan'`).Scan(&played)
	if played != 1 {
		t.Error("the twin's watched flag was lost")
	}
	var primary, backdrop string
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = 'scan' AND kind = 'Primary'`).Scan(&primary)
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = 'scan' AND kind = 'Backdrop'`).Scan(&backdrop)
	if primary != "/img/jf.jpg" || backdrop != "/img/scan-bd.jpg" {
		t.Errorf("images = %q / %q, want the twin's still and the kept backdrop", primary, backdrop)
	}
	var orphans int
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = 'jf'`).Scan(&orphans)
	if orphans != 0 {
		t.Errorf("%d image rows still point at the twin", orphans)
	}
	var provider string
	s.DB.QueryRow(`SELECT value FROM item_value WHERE item_id = 'scan' AND kind = 'provider:Tvdb'`).Scan(&provider)
	if provider != "123" {
		t.Error("the twin's provider id was lost")
	}
}

func TestMergeTwinsLeavesANamedRowItsName(t *testing.T) {
	s := legacyStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('a', 'Episode', 'Bad Dates', '/m/x.mkv', 0)`,
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('b', 'Episode', 'Bad Dates (import)', '/m/x.mkv', 0)`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.MergeTwins(); err != nil {
		t.Fatal(err)
	}
	var name string
	s.DB.QueryRow(`SELECT name FROM item WHERE path = '/m/x.mkv'`).Scan(&name)
	if name != "Bad Dates" {
		t.Errorf("name = %q, want the kept row's own", name)
	}
}

func TestMergeEmptySeriesFoldsTheHollowShowIntoTheFullOne(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, library_id, is_folder) VALUES ('full', 'Series', 'LINK CLICK', 'lib', 1)`,
		`INSERT INTO item (id, type, name, library_id, series_id, parent_id, is_folder) VALUES ('s1', 'Season', 'Season 1', 'lib', 'full', 'full', 1)`,
		`INSERT INTO item (id, type, name, library_id, series_id, season_id, is_folder) VALUES ('e1', 'Episode', 'Ep 1', 'lib', 'full', 's1', 0)`,
		`INSERT INTO item (id, type, name, library_id, is_folder) VALUES ('hollow', 'Series', 'LINK CLICK', 'lib', 1)`,
		`INSERT INTO item (id, type, name, library_id, series_id, parent_id, is_folder) VALUES ('hs1', 'Season', 'Season 1', 'lib', 'hollow', 'hollow', 1)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('hollow', 'Primary', 0, '/img/poster.jpg', 'p')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('hs1', 'Primary', 0, '/img/s1.jpg', 'q')`,
		`INSERT INTO user_data (item_id, is_favorite, updated_at) VALUES ('hollow', 1, '2026-01-01')`,
		// A different show of the same name in another library is left alone.
		`INSERT INTO item (id, type, name, library_id, is_folder) VALUES ('other', 'Series', 'LINK CLICK', 'lib2', 1)`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := s.MergeEmptySeries()
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Errorf("merged %d, want 1", n)
	}
	var series int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE type = 'Series'`).Scan(&series)
	if series != 2 {
		t.Errorf("%d series remain, want full and other", series)
	}
	var gone int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE id IN ('hollow', 'hs1')`).Scan(&gone)
	if gone != 0 {
		t.Error("the hollow show or its season survived")
	}
	var poster string
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = 'full' AND kind = 'Primary'`).Scan(&poster)
	if poster != "/img/poster.jpg" {
		t.Errorf("poster = %q, want the hollow show's", poster)
	}
	var fav int
	s.DB.QueryRow(`SELECT is_favorite FROM user_data WHERE item_id = 'full'`).Scan(&fav)
	if fav != 1 {
		t.Error("the favourite flag was lost")
	}
	var orphanImages int
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id IN ('hollow', 'hs1')`).Scan(&orphanImages)
	if orphanImages != 0 {
		t.Error("images still point at the removed rows")
	}
}

func TestDropEmptySeriesRemovesAShowWithNothingUnderIt(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('kept', 'Series', 'Babylon', 1)`,
		`INSERT INTO item (id, type, name, series_id, is_folder) VALUES ('e', 'Episode', 'Ep', 'kept', 0)`,
		`INSERT INTO item (id, type, name, is_folder) VALUES ('shell', 'Series', 'Babylon Berlin', 1)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, is_folder) VALUES ('shell-s1', 'Season', 'Season 1', 'shell', 'shell', 1)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('shell', 'Primary', 0, '/p.jpg', 't')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := s.DropEmptySeries()
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Errorf("dropped %d, want 1", n)
	}
	var left int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE id IN ('shell', 'shell-s1')`).Scan(&left)
	if left != 0 {
		t.Error("the shell or its season survived")
	}
	var kept int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE id = 'kept'`).Scan(&kept)
	if kept != 1 {
		t.Error("a show with episodes was dropped")
	}
	var img int
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = 'shell'`).Scan(&img)
	if img != 0 {
		t.Error("the shell's image row survived")
	}
}

// legacyStore is a database from before one-item-per-file was enforced, when
// twins could still be written — the data MergeTwins exists to mend.
func legacyStore(t *testing.T) *Store {
	s := testStore(t)
	if _, err := s.DB.Exec(`DROP INDEX IF EXISTS item_one_per_file`); err != nil {
		t.Fatal(err)
	}
	return s
}
