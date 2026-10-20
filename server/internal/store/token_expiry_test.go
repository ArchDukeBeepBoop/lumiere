package store

import (
	"path/filepath"
	"testing"
	"time"
)

func TestSignInsUnusedFor90DaysExpireAndUsedOnesAreTouched(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	s.DB.Exec(`INSERT INTO account (id, username, updated_at) VALUES ('a', 'me', '2026-01-01T00:00:00Z')`)
	s.IssueToken("fresh", "a", SessionInfo{})
	s.IssueToken("stale", "a", SessionInfo{})
	s.IssueToken("week", "a", SessionInfo{})
	old := time.Now().Add(-TokenIdleLimit - time.Hour).UTC().Format(time.RFC3339)
	week := time.Now().Add(-7 * 24 * time.Hour).UTC().Format(time.RFC3339)
	s.DB.Exec(`UPDATE token SET last_seen = ? WHERE token = ?`, old, HashToken("stale"))
	s.DB.Exec(`UPDATE token SET last_seen = ? WHERE token = ?`, week, HashToken("week"))
	if _, err := s.LookupToken("fresh"); err != nil {
		t.Fatal("a fresh sign-in was refused")
	}
	if _, err := s.LookupToken("stale"); err == nil {
		t.Fatal("a sign-in unused for 90 days still worked")
	}
	if _, err := s.LookupToken("week"); err != nil {
		t.Fatal("a sign-in used a week ago was refused")
	}
	var seen string
	s.DB.QueryRow(`SELECT last_seen FROM token WHERE token = ?`, HashToken("week")).Scan(&seen)
	if seen == week {
		t.Fatal("a used sign-in was not touched")
	}
}
