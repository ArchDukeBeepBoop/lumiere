package store

import (
	"strings"
	"testing"
)

func TestHealthCountsEachKindOfDamage(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('shell', 'Series', 'Hollow', 1)`,
		`INSERT INTO item (id, type, name, is_folder) VALUES ('show', 'Series', 'Show', 1)`,
		`INSERT INTO item (id, type, name, series_id, path, runtime_ticks, is_folder) VALUES ('e1', 'Episode', 'Show - 1x01', 'show', '/m/a.mkv', 100, 0)`,
		`INSERT INTO item (id, type, name, series_id, path, runtime_ticks, is_folder) VALUES ('e2', 'Episode', 'The Pilot', 'show', '/m/b.mkv', 100, 0)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('e2', 'Primary', 0, '/i.jpg', 't')`,
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('zero', 'Video', 'zeros', '/m/z.mkv', 0)`,
		`INSERT INTO item (id, type, name, production_year, path, runtime_ticks, is_folder) VALUES ('f1', 'Movie', 'Twice', 1999, '/m/t1.mkv', 9, 0), ('f2', 'Movie', 'Twice', 1999, '/m/t2.mkv', 9, 0)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('f1', 'Primary', 0, '/1.jpg', 'a'), ('f2', 'Primary', 0, '/2.jpg', 'b')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	issues, err := s.Health()
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]int{}
	for _, i := range issues {
		got[i.Kind] = i.Count
	}
	// DuplicateFilms counts films, not files: two copies of one film is one.
	want := map[string]int{"DuplicateFilms": 1, "EmptySeries": 1, "MissingArtwork": 2, "Unreadable": 1, "UnnamedEpisodes": 1}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %d, want %d", k, got[k], v)
		}
	}
}

func TestEpisodeGaps(t *testing.T) {
	for _, c := range []struct {
		have, want []int
	}{
		{[]int{1, 2, 4}, []int{3}},
		{[]int{4, 1, 2, 7}, []int{3, 5, 6}},
		{[]int{1, 2, 3}, nil},
		{[]int{1, 200}, nil},        // a numbering scheme, not 198 missing files
		{[]int{2, 2, 3}, nil},       // a doubled episode is not a gap
		{[]int{1, 3, 5, 7, 9}, nil}, // double-episode files
		{[]int{1, 3, 4}, []int{2}},
	} {
		got := EpisodeGaps(append([]int(nil), c.have...))
		if len(got) != len(c.want) {
			t.Errorf("%v → %v, want %v", c.have, got, c.want)
			continue
		}
		for i := range got {
			if got[i] != c.want[i] {
				t.Errorf("%v → %v, want %v", c.have, got, c.want)
			}
		}
	}
}

func TestTrailingGaps(t *testing.T) {
	if got := TrailingGaps([]int{1, 2, 3}, 5); len(got) != 2 || got[0] != 4 || got[1] != 5 {
		t.Errorf("got %v, want [4 5]", got)
	}
	if got := TrailingGaps([]int{1, 2, 3}, 0); got != nil {
		t.Errorf("unasked season gave %v", got)
	}
	if got := TrailingGaps([]int{1, 2}, 90); got != nil {
		t.Errorf("a differently split season gave %d gaps", len(got))
	}
}

func TestMissingEpisodesGroupByShowAndCanBeIgnored(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, series_id, series_name, season_id, parent_index_number, index_number, path, is_folder) VALUES
		 ('a1', 'Episode', 'a', 'op', 'One Piece', 's1', 1, 1, '/m/op/s1/1.mkv', 0),
		 ('a3', 'Episode', 'a', 'op', 'One Piece', 's1', 1, 3, '/m/op/s1/3.mkv', 0),
		 ('b1', 'Episode', 'b', 'op', 'One Piece', 's2', 2, 1, '/m/op/s2/1.mkv', 0),
		 ('b4', 'Episode', 'b', 'op', 'One Piece', 's2', 2, 4, '/m/op/s2/4.mkv', 0)`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	issue, err := s.missingEpisodes()
	if err != nil {
		t.Fatal(err)
	}
	if issue.Count != 3 || len(issue.Samples) != 1 || issue.Samples[0].ID != "op" {
		t.Fatalf("issue = %+v, want 3 missing grouped under One Piece", issue)
	}
	if len(issue.Samples[0].Parts) != 2 {
		t.Fatalf("parts = %+v, want the two seasons", issue.Samples[0].Parts)
	}
	if err := s.DismissHealth("MissingEpisodesSeason", "s1"); err != nil {
		t.Fatal(err)
	}
	if issue, _ = s.missingEpisodes(); issue.Count != 2 {
		t.Errorf("after ignoring season 1, count = %d, want season 2's 2", issue.Count)
	}
	if err := s.DismissHealth("MissingEpisodes", "op"); err != nil {
		t.Fatal(err)
	}
	if issue, _ = s.missingEpisodes(); issue.Count != 0 {
		t.Errorf("an ignored show still counts %d", issue.Count)
	}
	if n, _ := s.RestoreHealth(); n != 2 {
		t.Errorf("restored %d, want 2", n)
	}
}

func TestDriftWarnsOnlyWhenHistoryOrEpisodesFall(t *testing.T) {
	was := driftCounts{Items: 1000, Episodes: 800, Watched: 400}
	if w := DriftWarning(was, driftCounts{Items: 1010, Episodes: 810, Watched: 405}); w != "" {
		t.Errorf("growth warned: %s", w)
	}
	if w := DriftWarning(was, driftCounts{Items: 1000, Episodes: 800, Watched: 388}); w != "" {
		t.Errorf("a season unticked by hand warned: %s", w)
	}
	if w := DriftWarning(was, driftCounts{Items: 1000, Episodes: 800, Watched: 100}); w == "" {
		t.Error("most of the watch history vanishing was not raised")
	}
	if w := DriftWarning(was, driftCounts{Items: 900, Episodes: 700, Watched: 400}); w == "" {
		t.Error("an eighth of the episodes vanishing was not raised")
	}
	if w := DriftWarning(was, driftCounts{Items: 999, Episodes: 795, Watched: 400}); w != "" {
		t.Errorf("a handful of removals warned: %s", w)
	}
}

func TestAShrinkBetweenTwoNightsReachesLibraryHealth(t *testing.T) {
	s := testStore(t)
	for i := 0; i < 40; i++ {
		id := string(rune('a'+i%26)) + string(rune('a'+i/26))
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'Episode', 'e', 0)`, id)
		s.DB.Exec(`INSERT INTO user_data (item_id, played, updated_at) VALUES (?, 1, 'x')`, id)
	}
	// Night one: the baseline, no warning.
	if w, err := s.CheckDrift(); err != nil || w != "" {
		t.Fatalf("first night warned %q (%v)", w, err)
	}
	// By night two most of the watch history is gone.
	s.DB.Exec(`DELETE FROM user_data WHERE rowid % 4 <> 0`)
	if w, _ := s.CheckDrift(); w == "" {
		t.Fatal("the second night did not notice")
	}
	issues, err := s.Health()
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, i := range issues {
		if i.Kind == "LibraryShrank" && i.Count == 1 && len(i.Samples) == 1 {
			found = true
		}
	}
	if !found {
		t.Error("Library Health does not report the shrink")
	}
	// A quiet third night clears it.
	s.CheckDrift()
	if issues, _ = s.Health(); issues[len(issues)-1].Count != 0 {
		t.Error("the warning outlived a quiet night")
	}
}

func TestMisfiled(t *testing.T) {
	if got, ok := Misfiled("/tv/Show/Season 2/Show - S01E12 - Title.mkv", 2); !ok || got != "S01E12" {
		t.Errorf("got %q %v, want S01E12 flagged", got, ok)
	}
	if _, ok := Misfiled("/tv/Show/Season 2/Show - S02E03.mkv", 2); ok {
		t.Error("a correctly filed episode was flagged")
	}
	if _, ok := Misfiled("/tv/Show/Season 2/Show - S00E01 - OVA.mkv", 2); ok {
		t.Error("a special beside its season was flagged")
	}
	if _, ok := Misfiled("/tv/Show/Season 2/Show - 12.mkv", 2); ok {
		t.Error("a file with no season in its name was flagged")
	}
}

func TestFolderSeason(t *testing.T) {
	for path, want := range map[string]int{
		"/tv/Show/Season 2/x.mkv":                     2,
		"/tv/One Piece/Season 21 - Egghead Arc/x.mkv": 21,
		"/tv/Show/S03/x.mkv":                          3,
	} {
		if got, ok := FolderSeason(path); !ok || got != want {
			t.Errorf("%s → %d %v, want %d", path, got, ok, want)
		}
	}
	if _, ok := FolderSeason("/tv/Show/Extras/x.mkv"); ok {
		t.Error("a non-season folder named a season")
	}
}

func TestNamedSeasonTakesTheLastMarker(t *testing.T) {
	if n, named, ok := NamedSeason("/tv/3x3 Eyes/Season 1/3x3 Eyes - 1x01 - Transmigration.mkv"); !ok || n != 1 || named != "S01E01" {
		t.Errorf("got %d %q %v, want season 1", n, named, ok)
	}
	if m, ok := Majority([]int{2, 2, 2, 1}); !ok || m != 2 {
		t.Errorf("majority = %d %v", m, ok)
	}
	if _, ok := Majority([]int{1, 2, 3}); ok {
		t.Error("no clear majority was treated as one")
	}
}

func TestAGapNamesTheMisfiledFilesThatMayFillIt(t *testing.T) {
	gaps := HealthIssue{Samples: []HealthSample{{Name: "Aristocrat — 5 missing: season 1: 20, 21, 22, 23, 24"}, {Name: "Naruto — 1 missing: season 1: 12"}}}
	misfiled := HealthIssue{Samples: []HealthSample{{Name: "Aristocrat — S01E20 sits in the season 2 folder among season 2 files"}}}
	LinkGapsToMisfiled(&gaps, misfiled)
	if !strings.Contains(gaps.Samples[0].Name, "1 misfiled file below may be these") {
		t.Errorf("got %q", gaps.Samples[0].Name)
	}
	if strings.Contains(gaps.Samples[1].Name, "misfiled") {
		t.Error("a show with no strays was annotated")
	}
}

func TestASuggestedOrderIsOfferedUntilChosenOrIgnored(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('g', 'Series', 'Gintama', 1)`)
	s.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES ('g', 'tmdb:suggestedgroup', 'grp1` + "\t" + `DVD Order')`)
	issue, err := s.orderSuggestions()
	if err != nil || issue.Count != 1 || issue.Samples[0].Path != "grp1" {
		t.Fatalf("issue = %+v (%v)", issue, err)
	}
	s.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES ('g', 'tmdb:episodegroup', 'grp1')`)
	if issue, _ = s.orderSuggestions(); issue.Count != 0 {
		t.Error("a chosen order is still suggested")
	}
}
