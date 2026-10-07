package scanner

import (
	"io"
	"log/slog"
	"testing"
)

func TestLooseEpisodesAreSeated(t *testing.T) {
	s := testScanner(t)
	for _, q := range []string{
		// A show with no seasons at all.
		`INSERT INTO item (id, type, name, library_id, path, is_folder) VALUES ('elf', 'Series', 'Elf', 'lib', '/h/Elf', 1)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, index_number, is_folder) VALUES ('elf1', 'Episode', '1', 'elf', 'elf', 1, 0)`,
		// A show with seasons, and a loose OVA beside them.
		`INSERT INTO item (id, type, name, library_id, path, is_folder) VALUES ('ty', 'Series', 'Tylor', 'lib', '/a/Tylor', 1)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, index_number, is_folder) VALUES ('ty-s1', 'Season', 'Season 1', 'ty', 'ty', 1, 1)`,
		`INSERT INTO item (id, type, name, series_id, season_id, parent_id, parent_index_number, index_number, is_folder) VALUES ('ty1', 'Episode', '1', 'ty', 'ty-s1', 'ty-s1', 1, 1, 0)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, is_folder) VALUES ('ova', 'Episode', 'OVA', 'ty', 'ty', 0)`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := seatLooseEpisodes(s.Store.DB, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil || n != 2 {
		t.Fatalf("seated %d (%v), want 2", n, err)
	}
	check := func(id, wantSeasonName string, wantNumber int) {
		var name string
		var number int
		s.Store.DB.QueryRow(`SELECT s.name, e.parent_index_number FROM item e JOIN item s ON s.id = e.season_id
			WHERE e.id = ?`, id).Scan(&name, &number)
		if name != wantSeasonName || number != wantNumber {
			t.Errorf("%s is in %q (%d), want %q (%d)", id, name, number, wantSeasonName, wantNumber)
		}
	}
	check("elf1", "Season 1", 1)
	check("ova", "Specials", 0)
	check("ty1", "Season 1", 1)
	if again, _ := seatLooseEpisodes(s.Store.DB, slog.New(slog.NewTextHandler(io.Discard, nil))); again != 0 {
		t.Errorf("a second pass seated %d", again)
	}

	// And the way back: both episodes as they were, the made seasons gone.
	back, err := UndoSeating(s.Store.DB)
	if err != nil || back != 2 {
		t.Fatalf("undid %d (%v), want 2", back, err)
	}
	var seasonID, parent string
	s.Store.DB.QueryRow(`SELECT COALESCE(season_id, ''), parent_id FROM item WHERE id = 'ova'`).Scan(&seasonID, &parent)
	if seasonID != "" || parent != "ty" {
		t.Errorf("ova is back in %q under %q, want no season, under the show", seasonID, parent)
	}
	var made int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type = 'Season' AND name IN ('Specials') OR (type = 'Season' AND parent_id = 'elf')`).Scan(&made)
	if made != 0 {
		t.Errorf("%d seasons the repair made survived the undo", made)
	}
	var kept int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE id = 'ty-s1'`).Scan(&kept)
	if kept != 1 {
		t.Error("a season that existed before was removed")
	}
}

func TestEpisodesThatKnowTheirSeasonGoToIt(t *testing.T) {
	s := testScanner(t)
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	for _, q := range []string{
		// New Girl: a Specials season exists, and the episodes, from season
		// folders 1 and 2, arrived with no season.
		`INSERT INTO item (id, type, name, library_id, path, is_folder) VALUES ('ng', 'Series', 'New Girl', 'lib', '/tv/New Girl', 1)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, index_number, is_folder) VALUES ('ng-s0', 'Season', 'Specials', 'ng', 'ng', 0, 1)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, parent_index_number, index_number, is_folder) VALUES ('a', 'Episode', 'Pilot', 'ng', 'ng', 1, 1, 0)`,
		`INSERT INTO item (id, type, name, series_id, parent_id, parent_index_number, index_number, is_folder) VALUES ('b', 'Episode', 'Re-launch', 'ng', 'ng', 2, 1, 0)`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := seatLooseEpisodes(s.Store.DB, quiet); err != nil {
		t.Fatal(err)
	}
	for id, want := range map[string]string{"a": "Season 1", "b": "Season 2"} {
		var name string
		s.Store.DB.QueryRow(`SELECT z.name FROM item e JOIN item z ON z.id = e.season_id WHERE e.id = ?`, id).Scan(&name)
		if name != want {
			t.Errorf("%s seated in %q, want %q", id, name, want)
		}
	}
}

func TestReseatMovesWhatTheOldRuleMisfiled(t *testing.T) {
	s := testScanner(t)
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	for _, q := range []string{
		`INSERT INTO item (id, type, name, library_id, path, is_folder) VALUES ('ng', 'Series', 'New Girl', 'lib', '/tv/New Girl', 1)`,
		// What the old rule left: a Specials it made, holding season 3's episode.
		`INSERT INTO item (id, type, name, series_id, parent_id, index_number, is_folder) VALUES ('sp', 'Season', 'Specials', 'ng', 'ng', 0, 1)`,
		`INSERT INTO repair_log (step, item_id, created, at) VALUES ('seat', 'sp', 1, datetime('now'))`,
		`INSERT INTO item (id, type, name, series_id, season_id, parent_id, parent_index_number, index_number, is_folder) VALUES ('c', 'Episode', 'All In', 'ng', 'sp', 'sp', 3, 1, 0)`,
	} {
		if _, err := s.Store.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := reseatBySeasonNumber(s.Store.DB, quiet)
	if err != nil || n != 1 {
		t.Fatalf("moved %d (%v), want 1", n, err)
	}
	var name string
	s.Store.DB.QueryRow(`SELECT z.name FROM item e JOIN item z ON z.id = e.season_id WHERE e.id = 'c'`).Scan(&name)
	if name != "Season 3" {
		t.Errorf("moved into %q", name)
	}
	var left int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE id = 'sp'`).Scan(&left)
	if left != 0 {
		t.Error("the emptied Specials the old rule made should go")
	}
}
