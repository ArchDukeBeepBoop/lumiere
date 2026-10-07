package store

import (
	"testing"
	"time"
)

func addItem(t *testing.T, s *Store, id string) {
	t.Helper()
	if _, err := s.DB.Exec(
		`INSERT INTO item (id, type, name) VALUES (?, 'Episode', ?)`, id, id); err != nil {
		t.Fatal(err)
	}
}

func position(t *testing.T, s *Store, id string) int64 {
	t.Helper()
	u, err := s.UserDataFor(id)
	if err != nil {
		t.Fatal(err)
	}
	return u.PositionTicks
}

func TestRecordProgress(t *testing.T) {
	s := testStore(t)
	addItem(t, s, "ep1")

	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 100, SessionID: "s1"}); err != nil {
		t.Fatal(err)
	}
	if got := position(t, s, "ep1"); got != 100 {
		t.Fatalf("got %d, want 100", got)
	}

	// Later in the same session, moving forward.
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 500, SessionID: "s1"}); err != nil {
		t.Fatal(err)
	}
	if got := position(t, s, "ep1"); got != 500 {
		t.Fatalf("got %d, want 500", got)
	}

	// Seeking backwards within a session is a real thing a person does, and the
	// new position is the true one.
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 200, SessionID: "s1"}); err != nil {
		t.Fatal(err)
	}
	if got := position(t, s, "ep1"); got != 200 {
		t.Fatalf("seeking back was ignored: got %d, want 200", got)
	}
}

// The case a "keep the larger position" rule gets wrong, and the reason the
// ordering is done on sessions instead: starting something again from the
// beginning must not silently restore where you were last time.
func TestRewatchingFromTheStartIsNotUndone(t *testing.T) {
	s := testStore(t)
	addItem(t, s, "film")

	if err := s.RecordProgress(Progress{ItemID: "film", PositionTicks: 24_000_000_000, SessionID: "old"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(2 * time.Millisecond) // distinct started_at
	if err := s.RecordProgress(Progress{ItemID: "film", PositionTicks: 1_200_000_000, SessionID: "new"}); err != nil {
		t.Fatal(err)
	}
	if got := position(t, s, "film"); got != 1_200_000_000 {
		t.Fatalf("the new session's smaller position was discarded: got %d", got)
	}
}

// A report queued while the server was unreachable and replayed after a newer
// session has already written must not rewind the position.
func TestAStaleReplayDoesNotRewind(t *testing.T) {
	s := testStore(t)
	addItem(t, s, "ep1")

	// The old session is seen first, then a newer one takes over.
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 100, SessionID: "old"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(2 * time.Millisecond)
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 9_000, SessionID: "new"}); err != nil {
		t.Fatal(err)
	}
	// Now the old session's queued report finally arrives.
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 300, SessionID: "old"}); err != nil {
		t.Fatal(err)
	}
	if got := position(t, s, "ep1"); got != 9_000 {
		t.Fatalf("a stale replay overwrote a newer session: got %d, want 9000", got)
	}
}

// Every write must claim the row as local, or Batch 1's import rule cannot tell
// an evening's viewing from something it wrote itself and will overwrite it.
func TestWritesClaimTheRowAsLocal(t *testing.T) {
	s := testStore(t)
	addItem(t, s, "ep1")
	if _, err := s.DB.Exec(
		`INSERT INTO user_data (item_id, updated_at, source) VALUES ('ep1', '2020-01-01T00:00:00Z', 'jellyfin')`); err != nil {
		t.Fatal(err)
	}
	for name, write := range map[string]func() error{
		"progress": func() error { return s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 5}) },
		"played":   func() error { return s.SetPlayed("ep1", true) },
		"unplayed": func() error { return s.SetPlayed("ep1", false) },
		"favorite": func() error { return s.SetFavorite("ep1", true) },
	} {
		if _, err := s.DB.Exec(`UPDATE user_data SET source='jellyfin' WHERE item_id='ep1'`); err != nil {
			t.Fatal(err)
		}
		if err := write(); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		var source string
		if err := s.DB.QueryRow(`SELECT source FROM user_data WHERE item_id='ep1'`).Scan(&source); err != nil {
			t.Fatal(err)
		}
		if source != "local" {
			t.Errorf("%s left the row marked %q", name, source)
		}
	}
}

// §12.5: unwatching zeroes the position, the play count and the date. Leaving
// the position behind makes a freshly-unwatched episode resume at its final
// second — the exact bug fixed on the client this week.
func TestUnwatchingClearsTheResumePoint(t *testing.T) {
	s := testStore(t)
	addItem(t, s, "ep1")
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 8_000_000_000}); err != nil {
		t.Fatal(err)
	}
	if err := s.SetPlayed("ep1", true); err != nil {
		t.Fatal(err)
	}
	if err := s.SetPlayed("ep1", false); err != nil {
		t.Fatal(err)
	}
	u, err := s.UserDataFor("ep1")
	if err != nil {
		t.Fatal(err)
	}
	if u.Played || u.PositionTicks != 0 || u.PlayCount != 0 || u.LastPlayed != "" {
		t.Fatalf("unwatch left state behind: %+v", u)
	}
}

// Favouriting must not disturb where you were.
func TestFavouriteLeavesThePositionAlone(t *testing.T) {
	s := testStore(t)
	addItem(t, s, "ep1")
	if err := s.RecordProgress(Progress{ItemID: "ep1", PositionTicks: 4_200}); err != nil {
		t.Fatal(err)
	}
	if err := s.SetFavorite("ep1", true); err != nil {
		t.Fatal(err)
	}
	u, _ := s.UserDataFor("ep1")
	if !u.IsFavorite || u.PositionTicks != 4_200 {
		t.Fatalf("got %+v", u)
	}
}

func TestMarkingASeasonPlayedMarksItsEpisodes(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('s1', 'Series', 'Show', 1)`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, series_id) VALUES ('se1', 'Season', 'Season 1', 1, 's1', 's1')`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, series_id, season_id) VALUES ('e1', 'Episode', 'One', 0, 'se1', 's1', 'se1')`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, series_id, season_id) VALUES ('e2', 'Episode', 'Two', 0, 'se1', 's1', 'se1')`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, series_id, season_id, extra_type) VALUES ('nc', 'Episode', 'NCOP', 0, 'se1', 's1', 'se1', 'Clip')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.SetPlayed("se1", true); err != nil {
		t.Fatal(err)
	}
	var played int
	s.DB.QueryRow(`SELECT count(*) FROM user_data WHERE played = 1 AND item_id IN ('e1','e2')`).Scan(&played)
	if played != 2 {
		t.Errorf("episodes marked = %d, want 2", played)
	}
	// A creditless opening is not something anyone watched.
	var extra int
	s.DB.QueryRow(`SELECT count(*) FROM user_data WHERE item_id = 'nc'`).Scan(&extra)
	if extra != 0 {
		t.Error("an extra was marked watched")
	}
	// And back again, from the series this time.
	if err := s.SetPlayed("s1", false); err != nil {
		t.Fatal(err)
	}
	s.DB.QueryRow(`SELECT count(*) FROM user_data WHERE played = 1`).Scan(&played)
	if played != 0 {
		t.Errorf("still %d played after unmarking the series", played)
	}
}
