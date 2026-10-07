package store

import "testing"

func TestNextUpIsRememberedUntilWatchStateChanges(t *testing.T) {
	s := testStore(t)
	addEpisode(t, s, "e1", "show", 1, 1, true)
	addEpisode(t, s, "e2", "show", 1, 2, false)
	addEpisode(t, s, "e3", "show", 1, 3, false)
	first, err := s.NextUp("", 20)
	if err != nil || len(first) != 1 || first[0].ID != "e2" {
		t.Fatalf("first = %v (%v), want e2", ids(first), err)
	}
	// Watching e2 must move Next Up on, not replay the remembered answer.
	if err := s.SetPlayed("e2", true); err != nil {
		t.Fatal(err)
	}
	second, _ := s.NextUp("", 20)
	if len(second) != 1 || second[0].ID != "e3" {
		t.Errorf("after watching e2, next up = %v, want e3", ids(second))
	}
}

func ids(items []Item) []string {
	var out []string
	for _, i := range items {
		out = append(out, i.ID)
	}
	return out
}

func TestSpecialsAreNeverNextUp(t *testing.T) {
	s := testStore(t)
	addEpisode(t, s, "sp1", "show", 0, 1, true)
	addEpisode(t, s, "sp2", "show", 0, 2, false)
	addEpisode(t, s, "e1", "show", 1, 1, false)
	next, _ := s.NextUp("", 20)
	for _, n := range next {
		if n.ID == "sp2" {
			t.Error("a special was offered as next up")
		}
	}
}
