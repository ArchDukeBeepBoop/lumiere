package store

import "testing"

func TestChangeMarkerMovesWithWatchState(t *testing.T) {
	s := testStore(t)
	before := s.ChangeMarker()
	if _, err := s.DB.Exec(`INSERT INTO user_data (item_id, played, updated_at) VALUES ('x', 1, '2026-09-27T00:00:00Z')`); err != nil {
		t.Fatal(err)
	}
	if after := s.ChangeMarker(); after == before || after == "" {
		t.Fatalf("marker did not move: %q -> %q", before, after)
	}
}
