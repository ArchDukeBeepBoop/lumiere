package store

import "testing"

func TestAQueuedSeasonSkipsEpisodesThatHaveTheLanguage(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('show', 'Series', 'InuYasha', 1)`,
		`INSERT INTO item (id, type, name, series_name, series_id, season_id, path, is_folder) VALUES ('e1', 'Episode', 'One', 'InuYasha', 'show', 's1', '/m/1.mkv', 0)`,
		`INSERT INTO item (id, type, name, series_id, season_id, path, is_folder) VALUES ('e2', 'Episode', 'Two', 'show', 's1', '/m/2.mkv', 0)`,
		`INSERT INTO item (id, type, name, series_id, season_id, path, is_folder) VALUES ('e3', 'Episode', 'Three', 'show', 's2', '/m/3.mkv', 0)`,
		`INSERT INTO stream (item_id, idx, type, language) VALUES ('e2', 3, 'Subtitle', 'eng')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := s.QueueSubtitles("show", "s1", "en")
	if err != nil || n != 1 {
		t.Fatalf("queued %d (%v), want only e1 — e2 has English, e3 is another season", n, err)
	}
	if again, _ := s.QueueSubtitles("show", "s1", "en"); again != 0 {
		t.Errorf("queueing twice added %d", again)
	}
	next, _ := s.NextQueuedSubtitles(5)
	if len(next) != 1 || next[0].ItemID != "e1" {
		t.Fatalf("next = %+v", next)
	}
	if err := s.FinishQueuedSubtitle("e1", "en", "done", "synced +1.0 s"); err != nil {
		t.Fatal(err)
	}
	shows, err := s.SubtitleQueueByShow()
	if err != nil || len(shows) != 1 || shows[0].Series != "InuYasha" || shows[0].Done != 1 {
		t.Errorf("by show = %+v (%v)", shows, err)
	}
	s.FinishQueuedSubtitle("e1", "en", "failed", "none found")
	if n, _ := s.RetryFailedSubtitles(); n != 1 {
		t.Errorf("retried %d, want 1", n)
	}
	s.FinishQueuedSubtitle("e1", "en", "done", "synced +1.0 s")
	c, err := s.SubtitleQueueStatus()
	if err != nil || c.Waiting != 0 || c.Done != 1 || c.DoneToday != 1 {
		t.Errorf("status = %+v (%v)", c, err)
	}
}
