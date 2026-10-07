package scanner

import (
	"io"
	"log/slog"
	"testing"
	"time"
)

func TestTheStartupRepairRunsOncePerVersion(t *testing.T) {
	s := testScanner(t)
	s.Store.DB.Exec(`INSERT INTO item (id, type, name, library_id, is_folder) VALUES ('show', 'Series', 'S', 'lib', 1)`)
	s.Store.DB.Exec(`INSERT INTO item (id, type, name, series_id, parent_id, index_number, is_folder) VALUES ('e1', 'Episode', '1', 'show', 'show', 1, 0)`)
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	RepairIfNew(s.Store, quiet)
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if v, _ := s.Store.Meta(metaRepairVersion); v != "" {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	var season string
	s.Store.DB.QueryRow(`SELECT COALESCE(season_id, '') FROM item WHERE id = 'e1'`).Scan(&season)
	if season == "" {
		t.Fatal("the startup repair did not seat the episode")
	}
	if at, _ := s.Store.Meta("repaired_at"); at == "" {
		t.Error("the app was not told to re-read")
	}
}
