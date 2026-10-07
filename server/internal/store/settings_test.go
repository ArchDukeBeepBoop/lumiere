package store

import (
	"testing"
	"time"
)

func TestQuietHoursWrapMidnight(t *testing.T) {
	at := func(h int) time.Time { return time.Date(2026, 10, 1, h, 0, 0, 0, time.Local) }
	night := ServerSettings{QuietFrom: 22, QuietTo: 6}
	for h, want := range map[int]bool{23: true, 2: true, 6: false, 12: false, 22: true} {
		if night.InQuietHours(at(h)) != want {
			t.Errorf("22–6 at %d: want %v", h, want)
		}
	}
	if !(ServerSettings{QuietFrom: 3, QuietTo: 3}).InQuietHours(at(15)) {
		t.Error("equal hours mean any hour")
	}
}

func TestWatchedPercentMovesTheResumeCutoff(t *testing.T) {
	s := resumeFixture(t)
	v := s.Settings()
	v.WatchedPercent = 96
	s.SetSettings(v)
	items, _ := s.Resume(true, 20)
	found := false
	for _, it := range items {
		found = found || it.ID == "credits"
	}
	if !found {
		t.Error("at 96%, an episode stopped at 95% is still being watched")
	}
}

func TestStopPastTheWatchedPointMarksIt(t *testing.T) {
	s := resumeFixture(t)
	if !s.FinishIfWatched("half", 92) {
		t.Fatal("92 of 100 is past 90%")
	}
	if s.FinishIfWatched("unknown", 92) {
		t.Error("no runtime, no percentage")
	}
	var played int
	s.DB.QueryRow(`SELECT played FROM user_data WHERE item_id = 'half'`).Scan(&played)
	if played != 1 {
		t.Error("not marked")
	}
}

func TestResumeWeeksDropsAbandoned(t *testing.T) {
	s := resumeFixture(t)
	v := s.Settings()
	v.ResumeWeeks = 1
	s.SetSettings(v)
	if items, _ := s.Resume(true, 20); len(items) != 0 {
		t.Errorf("rows from September are past a week: %d left", len(items))
	}
}
