package schedule

import (
	"io"
	"log/slog"
	"testing"
	"time"

	"lumiere-server/internal/store"
)

type idle struct{ scanning bool }

func (i idle) StartScan() error { return nil }
func (i idle) Scanning() bool   { return i.scanning }

func keeper(t *testing.T, scan idle, asked *int) *Keeper {
	s, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return &Keeper{
		Store: s, Scan: scan, Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Naming: func() bool { *asked++; return true },
	}
}

func TestArtworkIsLookedUpOnEveryQuietTick(t *testing.T) {
	asked := 0
	k := keeper(t, idle{}, &asked)
	k.runOnce(time.Now())
	k.runOnce(time.Now())
	if asked != 2 {
		t.Errorf("naming offered %d times in two quiet ticks, want 2", asked)
	}
}

func TestNoArtworkLookupsWhileSomethingPlaysOrScans(t *testing.T) {
	asked := 0
	k := keeper(t, idle{}, &asked)
	now := time.Now().UTC().Format(time.RFC3339Nano)
	if _, err := k.Store.DB.Exec(`INSERT INTO user_data (item_id, updated_at, source) VALUES ('x', ?, 'local')`, now); err != nil {
		t.Fatal(err)
	}
	k.runOnce(time.Now())
	if asked != 0 {
		t.Error("a pass was offered while something played")
	}

	scanning := keeper(t, idle{scanning: true}, &asked)
	scanning.runOnce(time.Now())
	if asked != 0 {
		t.Error("a pass was offered during a scan, which starts its own")
	}
}
