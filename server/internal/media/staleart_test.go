package media

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

// A database with just the two tables this pass reads. The store's own
// schema would import the store, which imports this package.
func artDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	for _, q := range []string{
		`CREATE TABLE item (id TEXT PRIMARY KEY, type TEXT, name TEXT, path TEXT,
		    is_folder INTEGER, runtime_ticks INTEGER, date_created TEXT)`,
		`CREATE TABLE image (item_id TEXT, kind TEXT, idx INTEGER, path TEXT, tag TEXT,
		    PRIMARY KEY (item_id, kind, idx))`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	return db
}

func TestStaleArtworkClearsRowsWhosePicturesAreGone(t *testing.T) {
	s := struct{ DB *sql.DB }{artDB(t)}
	dir := t.TempDir()
	live := filepath.Join(dir, "there.jpg")
	if err := os.WriteFile(live, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, q := range []string{
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('gone', 'Episode', 'A', '` + live + `', 0)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('gone', 'Primary', 0, '` + dir + `/missing.jpg', 't')`,
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('kept', 'Episode', 'B', '/m/b.mkv', 0)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('kept', 'Primary', 0, '` + live + `', 'u')`,
		// One picture readable, one not: the tile still draws, so it is left alone.
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('half', 'Episode', 'C', '/m/c.mkv', 0)`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('half', 'Primary', 0, '` + live + `', 'v')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('half', 'Backdrop', 0, '` + dir + `/missing2.jpg', 'w')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}

	// The video is on disk (the stand-in file) — a picture is only worth
	// retaking from a video that is there.
	found, err := staleArtwork(s.DB, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(found) != 1 || found[0].id != "gone" {
		t.Fatalf("stale = %v, want just the item whose picture is missing", found)
	}
	var rows int
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = 'gone'`).Scan(&rows)
	if rows != 0 {
		t.Error("the unreadable image row was not cleared")
	}
	// The half item keeps its readable poster and loses only the backdrop
	// whose file is gone.
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = 'kept'`).Scan(&rows)
	if rows != 1 {
		t.Errorf("%d image rows on the readable item, want 1", rows)
	}
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = 'half'`).Scan(&rows)
	if rows != 2 {
		t.Errorf("%d image rows on the half-readable item, want both left alone", rows)
	}
}

func TestStaleArtworkReachesOldRowsNotJustRecentOnes(t *testing.T) {
	db := artDB(t)
	dir := t.TempDir()
	// Two thousand healthy recent rows in front of one old broken one: the
	// blanks people see are old, and a recency cap never reached them.
	live := filepath.Join(dir, "there.jpg")
	if err := os.WriteFile(live, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2000; i++ {
		id := "ok" + string(rune('a'+i%26)) + string(rune('a'+i/26))
		if _, err := db.Exec(
			`INSERT INTO item (id, type, name, path, is_folder, date_created) VALUES (?, 'Video', 'A', '/m/a.mkv', 0, '2026-09-01')`, id,
		); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(
			`INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?, 'Primary', 0, ?, 't')`, id, live,
		); err != nil {
			t.Fatal(err)
		}
	}
	for _, q := range []string{
		`INSERT INTO item (id, type, name, path, is_folder, date_created) VALUES ('old', 'Video', 'Old', '` + live + `', 0, '2025-02-09')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('old', 'Primary', 0, '` + dir + `/gone.jpg', 't')`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}

	found, err := staleArtwork(db, 500)
	if err != nil {
		t.Fatal(err)
	}
	if len(found) != 1 || found[0].id != "old" {
		t.Fatalf("stale = %v, want the old broken row", found)
	}
}

func TestBareCountsAnItemWithNoPrimaryPicture(t *testing.T) {
	db := artDB(t)
	// A backdrop and nothing else: the tile draws the Primary, so this is
	// as blank as a row with no pictures at all.
	for _, q := range []string{
		`INSERT INTO item (id, type, name, path, is_folder, date_created) VALUES ('backdroponly', 'Video', 'A', '/m/a.mkv', 0, '2026-01-01')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('backdroponly', 'Backdrop', 0, '/img/b.jpg', 't')`,
		`INSERT INTO item (id, type, name, path, is_folder, date_created) VALUES ('hasprimary', 'Video', 'B', '/m/b.mkv', 0, '2026-01-01')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('hasprimary', 'Primary', 0, '/img/p.jpg', 'u')`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	rows, err := db.Query(`
		SELECT id FROM item
		WHERE is_folder = 0 AND path IS NOT NULL AND path <> ''
		  AND type IN ('Video', 'Movie', 'Episode')
		  AND NOT EXISTS (
			SELECT 1 FROM image g WHERE g.item_id = item.id AND g.kind = 'Primary'
		  )`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		ids = append(ids, id)
	}
	if len(ids) != 1 || ids[0] != "backdroponly" {
		t.Errorf("bare = %v, want just the item with no Primary", ids)
	}
}
