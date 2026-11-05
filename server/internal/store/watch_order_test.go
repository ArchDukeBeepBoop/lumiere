package store

import (
	"reflect"
	"testing"
)

func TestAWatchOrderIsSharedAndReplacedWhole(t *testing.T) {
	s := testStore(t)
	if got, _ := s.WatchOrder("mono"); len(got) != 0 {
		t.Fatalf("none arranged yet: %v", got)
	}
	if err := s.SetWatchOrder("mono", []string{"kizu", "bake", "nise", "bake"}); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.WatchOrder("mono"); !reflect.DeepEqual(got, []string{"kizu", "bake", "nise"}) {
		t.Fatalf("in the order given, each once: %v", got)
	}
	s.SetWatchOrder("mono", []string{"nise", "kizu"})
	if got, _ := s.WatchOrder("mono"); !reflect.DeepEqual(got, []string{"nise", "kizu"}) {
		t.Fatalf("replaced, not merged: %v", got)
	}
	s.SetWatchOrder("mono", nil)
	if got, _ := s.WatchOrder("mono"); len(got) != 0 {
		t.Fatalf("cleared: %v", got)
	}
}
