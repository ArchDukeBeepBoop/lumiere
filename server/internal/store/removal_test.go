package store

import "testing"

func TestRemoveCascadesAndRestoreBringsItAllBack(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('s1', 'Series', 'Show', 1, '/m/Show')`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, series_id) VALUES ('se1', 'Season', 'Season 1', 1, 's1', 's1')`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, series_id, season_id, path, index_number)
		 VALUES ('e1', 'Episode', 'Ep 1', 0, 'se1', 's1', 'se1', '/m/Show/e1.mkv', 1)`,
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('m1', 'Movie', 'Other', 0, '/m/Other.mkv')`,
		`INSERT INTO user_data (item_id, played, updated_at) VALUES ('e1', 1, 'now')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}

	moved, err := s.Remove("s1")
	if err != nil || moved != 3 {
		t.Fatalf("remove: moved %d, err %v", moved, err)
	}
	var left int
	s.DB.QueryRow(`SELECT count(*) FROM item`).Scan(&left)
	if left != 1 {
		t.Errorf("items left = %d, want just the other film", left)
	}
	removed, _ := s.Removed()
	if len(removed) != 1 || removed[0].ID != "s1" || removed[0].Members != 3 {
		t.Errorf("removed listing = %+v", removed)
	}

	restored, err := s.Restore("s1")
	if err != nil || restored != 3 {
		t.Fatalf("restore: %d, %v", restored, err)
	}
	var index int
	var played int
	s.DB.QueryRow(`SELECT index_number FROM item WHERE id='e1'`).Scan(&index)
	s.DB.QueryRow(`SELECT played FROM user_data WHERE item_id='e1'`).Scan(&played)
	if index != 1 || played != 1 {
		t.Errorf("episode came back wrong: index %d played %d", index, played)
	}
	var gone int
	s.DB.QueryRow(`SELECT count(*) FROM removed_item`).Scan(&gone)
	if gone != 0 {
		t.Error("restore left rows in removed_item")
	}
}

func TestPurgeDropsEverythingHangingOffARow(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('m1', 'Movie', 'Film', 0, '/m/f.mkv')`,
		`INSERT INTO image (item_id, kind, path, tag) VALUES ('m1', 'Primary', '/art/p.jpg', 't')`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('m1', 'genre', 'Drama')`,
		`INSERT INTO user_data (item_id, played, updated_at) VALUES ('m1', 1, 'now')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.Purge([]string{"m1"}); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"item", "image", "item_value", "user_data"} {
		var n int
		s.DB.QueryRow(`SELECT count(*) FROM ` + table).Scan(&n)
		if n != 0 {
			t.Errorf("%s still has %d rows", table, n)
		}
	}
}
