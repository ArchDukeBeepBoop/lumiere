package store

import (
	"path/filepath"
	"testing"
)

// A small library built by hand, so Next Up's rule can be stated as facts about
// known episodes rather than inferred from 25,000 real ones.
func testStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func addEpisode(t *testing.T, s *Store, id, series string, season, number int, played bool) {
	t.Helper()
	_, err := s.DB.Exec(
		`INSERT INTO item (id, type, name, series_id, parent_index_number, index_number)
		 VALUES (?, 'Episode', ?, ?, ?, ?)`, id, id, series, season, number)
	if err != nil {
		t.Fatal(err)
	}
	if !played {
		return
	}
	if _, err := s.DB.Exec(
		`INSERT INTO user_data (item_id, played, updated_at, last_played)
		 VALUES (?, 1, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z')`, id); err != nil {
		t.Fatal(err)
	}
}

func TestNextUp(t *testing.T) {
	s := testStore(t)

	// One series watched to the end of episode 2.
	addEpisode(t, s, "a1", "seriesA", 1, 1, true)
	addEpisode(t, s, "a2", "seriesA", 1, 2, true)
	addEpisode(t, s, "a3", "seriesA", 1, 3, false)
	addEpisode(t, s, "a4", "seriesA", 1, 4, false)

	// A series watched out of order, with a gap: episode 2 was skipped but the
	// viewer is on season 2. Parking Next Up on the skipped episode forever is
	// the failure this rule exists to avoid.
	addEpisode(t, s, "b1", "seriesB", 1, 1, true)
	addEpisode(t, s, "b2", "seriesB", 1, 2, false)
	addEpisode(t, s, "b3", "seriesB", 2, 1, true)
	addEpisode(t, s, "b4", "seriesB", 2, 2, false)

	// A series nobody has started must not appear at all: that is what a Latest
	// shelf is for, and folding it in turns Next Up into a list of things never
	// begun.
	addEpisode(t, s, "c1", "seriesC", 1, 1, false)

	// A series watched to the very end has nothing next.
	addEpisode(t, s, "d1", "seriesD", 1, 1, true)

	got, err := s.NextUp("", 20)
	if err != nil {
		t.Fatal(err)
	}
	ids := map[string]bool{}
	for _, it := range got {
		ids[it.ID] = true
	}

	if !ids["a3"] {
		t.Error("seriesA should offer episode 3, the first unwatched after the furthest point")
	}
	if ids["a4"] {
		t.Error("seriesA offered two episodes; Next Up is one per series")
	}
	if !ids["b4"] {
		t.Error("seriesB should offer S2E2, not the episode skipped back in season 1")
	}
	if ids["b2"] {
		t.Error("seriesB offered the skipped S1E2 rather than moving on")
	}
	if ids["c1"] {
		t.Error("a series nobody has started must not appear")
	}
	if len(got) != 2 {
		t.Errorf("expected exactly seriesA and seriesB, got %d items", len(got))
	}
}

func TestNextUpCanBeScopedToOneSeries(t *testing.T) {
	s := testStore(t)
	addEpisode(t, s, "a1", "seriesA", 1, 1, true)
	addEpisode(t, s, "a2", "seriesA", 1, 2, false)
	addEpisode(t, s, "b1", "seriesB", 1, 1, true)
	addEpisode(t, s, "b2", "seriesB", 1, 2, false)

	got, err := s.NextUp("seriesA", 20)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].ID != "a2" {
		t.Fatalf("got %d items, want just a2", len(got))
	}
}

// A series' ChildCount is its seasons, and nothing else.
//
// The library this was found in parents 9,267 episodes straight to the series
// rather than to a season, so counting direct children told the poster card
// "Hikaru no Go, 80 seasons" when it has 4.
func TestSeriesChildCountCountsSeasonsNotStrayEpisodes(t *testing.T) {
	s := testStore(t)

	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES ('show', 'Series', 'Show');
		INSERT INTO item (id, type, name, parent_id, series_id)
		VALUES ('s1', 'Season', 'Season 1', 'show', 'show'),
		       ('s2', 'Season', 'Season 2', 'show', 'show');
		INSERT INTO item (id, type, name, parent_id, series_id, season_id)
		VALUES ('e1', 'Episode', 'E1', 'show', 'show', 's1'),
		       ('e2', 'Episode', 'E2', 'show', 'show', 's1'),
		       ('e3', 'Episode', 'E3', 's2', 'show', 's2')`); err != nil {
		t.Fatal(err)
	}

	it, err := s.ItemByID("show")
	if err != nil {
		t.Fatal(err)
	}
	if it.ChildCount == nil {
		t.Fatal("no ChildCount emitted for a series")
	}
	if *it.ChildCount != 2 {
		t.Errorf("ChildCount = %d, want 2 seasons", *it.ChildCount)
	}
	// The episodes are still all there, just counted as what they are.
	if it.RecursiveItemCount == nil || *it.RecursiveItemCount != 3 {
		t.Errorf("RecursiveItemCount = %v, want 3 episodes", it.RecursiveItemCount)
	}
}

// An empty season is not a season anyone can open.
//
// A scan leaves a "Season Unknown" holding nothing beside the real one on every
// show it has not finished identifying, and counting it told the card that a
// one-season show had two.
func TestSeriesChildCountIgnoresEmptySeasons(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES ('show', 'Series', 'Show');
		INSERT INTO item (id, type, name, parent_id, series_id)
		VALUES ('s1', 'Season', 'Season 1', 'show', 'show'),
		       ('s0', 'Season', 'Season Unknown', 'show', 'show');
		INSERT INTO item (id, type, name, parent_id, series_id, season_id)
		VALUES ('e1', 'Episode', 'E1', 's1', 'show', 's1')`); err != nil {
		t.Fatal(err)
	}

	it, err := s.ItemByID("show")
	if err != nil {
		t.Fatal(err)
	}
	if it.ChildCount == nil || *it.ChildCount != 1 {
		t.Errorf("ChildCount = %v, want 1 season with episodes in it", it.ChildCount)
	}
}

// A sync that has written the seasons but not yet the episodes must not report a
// show with no seasons at all.
func TestSeriesChildCountFallsBackWhenNothingIsCachedYet(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name) VALUES ('show', 'Series', 'Show');
		INSERT INTO item (id, type, name, parent_id, series_id)
		VALUES ('s1', 'Season', 'Season 1', 'show', 'show'),
		       ('s2', 'Season', 'Season 2', 'show', 'show')`); err != nil {
		t.Fatal(err)
	}

	it, err := s.ItemByID("show")
	if err != nil {
		t.Fatal(err)
	}
	if it.ChildCount == nil || *it.ChildCount != 2 {
		t.Errorf("ChildCount = %v, want the raw 2", it.ChildCount)
	}
}

func TestExtrasAreFoundWhereTheyAre(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		// A show whose extras sit in a folder the scan made, not under it.
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('acca', 'Series', 'ACCA', 1, '/a/ACCA 13')`,
		`INSERT INTO item (id, type, name, is_folder, path, parent_id, extra_type) VALUES ('op', 'Video', 'Opening', 0, '/a/ACCA 13/Extras/Opening.mkv', 'xfolder', 'Clip')`,
		// A film alone in its folder, and two films sharing one.
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('alone', 'Movie', 'Alone', 0, '/m/Alone (2019)/Alone.mkv')`,
		`INSERT INTO item (id, type, name, is_folder, path, extra_type) VALUES ('mk', 'Video', 'Making of', 0, '/m/Alone (2019)/Featurettes/Making.mkv', 'BehindTheScenes')`,
		`INSERT INTO item (id, type, name, is_folder, path) VALUES ('f1', 'Movie', 'One', 0, '/flat/One.mkv'), ('f2', 'Movie', 'Two', 0, '/flat/Two.mkv')`,
		`INSERT INTO item (id, type, name, is_folder, path, extra_type) VALUES ('tr', 'Video', 'Trailer', 0, '/flat/Extras/Two trailer.mkv', 'Trailer')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	check := func(id string, want int) {
		got, err := s.Extras(id)
		if err != nil || len(got) != want {
			t.Errorf("%s: %d extras (%v), want %d", id, len(got), err, want)
		}
	}
	check("acca", 1)
	check("alone", 1)
	check("f1", 0)
}
