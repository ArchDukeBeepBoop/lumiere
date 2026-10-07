// Package trial runs the server's startup and repair passes against a copy of
// a real library, and reports what they would change.
//
// Fixtures prove a rule; only the real library proves the rule meets the
// data. The episode-numbering assumption this session started from was wrong
// in a way no fixture showed, and a dry run on a copy is what caught it. This
// makes that dry run one command:
//
//	LUMIERE_TRIAL_DB="$HOME/Library/Application Support/LumiereServer/library.db" \
//	    go test ./internal/trial -v -count=1
//
// Skipped unless the variable is set, so `go test ./...` never touches a real
// library. The original is only read: SQLite's backup writes a copy into a
// temporary folder, and everything runs there.
package trial

import (
	"database/sql"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	_ "modernc.org/sqlite"

	"lumiere-server/internal/scanner"
	"lumiere-server/internal/store"
)

func TestTrialOnARealLibrary(t *testing.T) {
	source := os.Getenv("LUMIERE_TRIAL_DB")
	if source == "" {
		t.Skip("set LUMIERE_TRIAL_DB to a library.db to run the trial")
	}
	dir := t.TempDir()
	original, err := sql.Open("sqlite", "file:"+source+"?mode=ro")
	if err != nil {
		t.Fatal(err)
	}
	copyPath := filepath.Join(dir, "library.db")
	if _, err := original.Exec(`VACUUM INTO ?`, copyPath); err != nil {
		t.Fatal(err)
	}
	original.Close()

	clock := time.Now()
	gonePictures := goneTilePictures(t, copyPath)
	before := snapshot(t, copyPath)
	t.Logf("before counted in %s", time.Since(clock).Round(time.Millisecond))
	clock = time.Now()

	// Everything a server start does, then the repair pass a scan runs.
	s, err := store.Open(dir)
	if err != nil {
		t.Fatalf("the server would not start on this library: %v", err)
	}
	defer s.Close()
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	t.Logf("opened in %s", time.Since(clock).Round(time.Millisecond))
	clock = time.Now()
	if _, err := scanner.Repair(s.DB, quiet); err != nil {
		t.Fatalf("the repair pass fails on this library: %v", err)
	}
	t.Logf("repaired in %s", time.Since(clock).Round(time.Millisecond))
	clock = time.Now()
	if _, err := s.TitleUnmatchedEpisodes(); err != nil {
		t.Fatalf("file titles fail on this library: %v", err)
	}

	after := snapshot(t, copyPath)
	counted := time.Since(clock)
	t.Logf("after counted in %s", counted.Round(time.Millisecond))
	// The health report runs after every sync. A query that is instant on a
	// test database and minutes on this one — as one join was — fails here.
	if counted > 10*time.Second {
		t.Errorf("the health report took %s on this library; it runs after every sync", counted.Round(time.Second))
	}
	for _, k := range []string{"items", "episodes", "watched", "unseated", "wrongSeason", "blankShows", "strayCollections", "emptyCollections", "collectionMembers"} {
		t.Logf("%-10s %7d → %7d", k, before[k], after[k])
	}
	for kind := range after {
		if kind == "items" || kind == "episodes" || kind == "watched" || kind == "unseated" || kind == "wrongSeason" || kind == "blankShows" || strings.HasSuffix(kind, "Collections") || kind == "collectionMembers" || kind == "LibraryShrank" || kind == "BackupUnusable" || kind == "OrderSuggestions" || kind == "UnplacedFiles" {
			continue
		}
		t.Logf("%-16s %7d → %7d", kind, before[kind], after[kind])
		// A picture whose file is gone was a blank tile counted as fine; with
		// its row dropped it is counted as missing, until the frame pass —
		// which the trial does not run — takes it again. Growth up to that
		// many is the count becoming honest, not damage.
		if kind == "MissingArtwork" && after[kind] <= before[kind]+gonePictures {
			continue
		}
		if after[kind] > before[kind] {
			t.Errorf("%s grew from %d to %d", kind, before[kind], after[kind])
		}
	}
	// Every show that has episodes must list some.
	if after["wrongSeason"] > 0 {
		t.Errorf("%d episodes sit in a season other than their own", after["wrongSeason"])
	}
	if after["strayCollections"] > 0 {
		t.Errorf("%d collections sit outside the Collections library", after["strayCollections"])
	}
	if after["collectionMembers"] < before["collectionMembers"] {
		t.Errorf("collection members fell from %d to %d", before["collectionMembers"], after["collectionMembers"])
	}
	if after["blankShows"] > 0 {
		t.Errorf("%d shows would open on an empty episode list", after["blankShows"])
	}
	// Watch history is the one thing a rescan cannot give back.
	if after["watched"] < before["watched"] {
		t.Errorf("watched rows fell from %d to %d", before["watched"], after["watched"])
	}
	// A pass that removes more than one item in fifty is a pass to look at.
	if lost := before["episodes"] - after["episodes"]; lost*50 > before["episodes"] {
		t.Errorf("%d episodes would be removed", lost)
	}
}

// snapshot counts the things a pass could damage.
func snapshot(t *testing.T, path string) map[string]int {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	counts := map[string]int{}
	for k, q := range map[string]string{
		"items":             `SELECT count(*) FROM item`,
		"episodes":          `SELECT count(*) FROM item WHERE type = 'Episode'`,
		"watched":           `SELECT count(*) FROM user_data WHERE played = 1`,
		"strayCollections":  `SELECT count(*) FROM item WHERE type = 'BoxSet' AND COALESCE(parent_id, '') = ''`,
		"emptyCollections":  `SELECT count(*) FROM item b WHERE b.type = 'BoxSet' AND NOT EXISTS (SELECT 1 FROM link WHERE parent_id = b.id)`,
		"collectionMembers": `SELECT count(*) FROM link l JOIN item b ON b.id = l.parent_id WHERE b.type = 'BoxSet'`,
		// Episodes in a season other than the one their own number names.
		"wrongSeason": `SELECT count(*) FROM item e JOIN item z ON z.id = e.season_id
			WHERE e.type = 'Episode' AND e.parent_index_number IS NOT NULL
			AND z.id IN (SELECT item_id FROM repair_log WHERE step = 'seat' AND created = 1)
			AND COALESCE(z.index_number, -1) <> e.parent_index_number`,
		"unseated": `SELECT count(*) FROM item WHERE type = 'Episode' AND season_id IS NULL`,
		// A show with episodes whose page would list none: no season of it
		// holds a single one. What "No episodes cached yet" looked like.
		"blankShows": `SELECT count(*) FROM item s WHERE s.type = 'Series'
			AND EXISTS (SELECT 1 FROM item e WHERE e.series_id = s.id AND e.type = 'Episode')
			AND NOT EXISTS (SELECT 1 FROM item e JOIN item z ON z.id = e.season_id
			                WHERE e.series_id = s.id AND e.type = 'Episode' AND z.type = 'Season')`,
	} {
		var n int
		db.QueryRow(q).Scan(&n)
		counts[k] = n
	}
	// A table a newer server adds at startup, which the untouched copy has
	// not got yet. Empty, it changes no count.
	db.Exec(`CREATE TABLE IF NOT EXISTS health_dismissed (kind TEXT NOT NULL, key TEXT NOT NULL, PRIMARY KEY (kind, key))`)
	issues, err := (&store.Store{DB: db}).Health()
	if err != nil {
		t.Fatal(err)
	}
	for _, i := range issues {
		counts[i.Kind] = i.Count
	}
	return counts
}

func goneTilePictures(t *testing.T, path string) int {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	rows, err := db.Query(`SELECT g.path FROM image g JOIN item i ON i.id = g.item_id
		WHERE g.kind = 'Primary' AND i.type IN ('Movie','Episode','Video') AND i.is_folder = 0`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	gone := 0
	for rows.Next() {
		var p string
		rows.Scan(&p)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			gone++
		}
	}
	return gone
}
