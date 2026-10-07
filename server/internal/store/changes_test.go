package store

import (
	"testing"
	"time"
)

func TestChangeLogFollowsAddEditWatchAndRemove(t *testing.T) {
	s := testStore(t)
	start := s.LatestChange()
	if start < 1 {
		t.Fatalf("the first token is 1, not %d", start)
	}
	if c, _ := s.ChangesSince(0, 100); !c.Reset || c.Next != start {
		t.Fatalf("no token means read everything: %+v", c)
	}

	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('a', 'Movie', 'Alien', 0), ('b', 'Movie', 'Brazil', 0)`)
	c, _ := s.ChangesSince(start, 100)
	if c.Reset || len(c.Changed) != 2 || len(c.Removed) != 0 {
		t.Fatalf("two added: %+v", c)
	}

	// Rewriting what is already there is not a change — the scanner does it
	// to thousands of rows a pass.
	mark := c.Next
	s.DB.Exec(`UPDATE item SET name = name`)
	if c, _ := s.ChangesSince(mark, 100); len(c.Changed) != 0 {
		t.Fatalf("an unchanged rewrite was logged: %+v", c)
	}

	s.DB.Exec(`UPDATE item SET name = 'Aliens' WHERE id = 'a'`)
	s.SetPlayed("b", true)
	s.DB.Exec(`DELETE FROM item WHERE id = 'a'`)
	c, _ = s.ChangesSince(mark, 100)
	if len(c.Changed) != 1 || c.Changed[0] != "b" || len(c.Removed) != 1 || c.Removed[0] != "a" {
		t.Fatalf("edited then removed reads as removed; watched reads as changed: %+v", c)
	}

	if c, _ := s.ChangesSince(c.Next+50, 100); !c.Reset {
		t.Error("a token from another database must reset")
	}
}

func TestChangesComeInPages(t *testing.T) {
	s := testStore(t)
	start := s.LatestChange()
	for _, id := range []string{"a", "b", "c"} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'Movie', ?, 0)`, id, id)
	}
	first, _ := s.ChangesSince(start, 2)
	if !first.More || len(first.Changed) != 2 {
		t.Fatalf("%+v", first)
	}
	rest, _ := s.ChangesSince(first.Next, 2)
	if rest.More || len(rest.Changed) != 1 || rest.Changed[0] != "c" {
		t.Fatalf("%+v", rest)
	}
}

func TestWaitingReturnsWhenSomethingChanges(t *testing.T) {
	s := testStore(t)
	since := s.LatestChange()
	go func() {
		time.Sleep(200 * time.Millisecond)
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('x', 'Movie', 'X', 0)`)
	}()
	began := time.Now()
	if got := s.WaitForChange(since, 10*time.Second, nil); got <= since {
		t.Fatal("returned without a change")
	}
	if time.Since(began) > 3*time.Second {
		t.Error("waited past the change")
	}
}

func TestTrimmingKeepsTheCounterAndResetsOldTokens(t *testing.T) {
	s := testStore(t)
	old := s.LatestChange()
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('a', 'Movie', 'A', 0)`)
	s.DB.Exec(`UPDATE change_log SET at = '2000-01-01T00:00:00Z'`)
	if err := s.TrimChanges(); err != nil {
		t.Fatal(err)
	}
	latest := s.LatestChange()
	if latest <= old {
		t.Fatal("the counter went back")
	}
	if c, _ := s.ChangesSince(old, 10); !c.Reset {
		t.Error("a token from before the trim must read everything")
	}
	if c, _ := s.ChangesSince(latest, 10); c.Reset {
		t.Error("a current token must not reset")
	}
}
