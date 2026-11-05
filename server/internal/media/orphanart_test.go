package media

import (
	"database/sql"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	_ "modernc.org/sqlite"
)

func TestOldArtworkIsRemovedOnlyWhenNothingNamesIt(t *testing.T) {
	root := t.TempDir()
	db, err := sql.Open("sqlite", filepath.Join(t.TempDir(), "x.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.Exec(`CREATE TABLE image (item_id TEXT, kind TEXT, idx INT, path TEXT, tag TEXT)`)
	old := time.Now().Add(-48 * time.Hour)
	write := func(rel string, aged bool) string {
		p := filepath.Join(root, rel)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte("jpeg"), 0o644)
		if aged {
			os.Chtimes(p, old, old)
		}
		return p
	}
	kept := write("metadata/a-primary.jpg", true)
	replaced := write("identified/a-old.jpg", true)
	fresh := write("frames/b.jpg", false)
	resized := write("an/il/x.jpg", true)
	for i := 0; i < 6; i++ {
		db.Exec(`INSERT INTO image VALUES (?, 'Primary', 0, ?, 't')`, i, write(filepath.Join("metadata", string(rune('c'+i))+".jpg"), true))
	}
	db.Exec(`INSERT INTO image VALUES ('a', 'Primary', 0, ?, 't')`, kept)

	n, _ := SweepOrphanArt(db, root, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if n != 1 {
		t.Fatalf("removed %d, want only the replaced one", n)
	}
	for _, p := range []string{kept, fresh, resized} {
		if _, err := os.Stat(p); err != nil {
			t.Fatalf("%s should stay", p)
		}
	}
	if _, err := os.Stat(replaced); !os.IsNotExist(err) {
		t.Fatal("the replaced picture should be gone")
	}
}

func TestOldArtworkSweepStopsWhenMostIsUnreferenced(t *testing.T) {
	root := t.TempDir()
	db, _ := sql.Open("sqlite", filepath.Join(t.TempDir(), "x.db"))
	defer db.Close()
	db.Exec(`CREATE TABLE image (item_id TEXT, kind TEXT, idx INT, path TEXT, tag TEXT)`)
	db.Exec(`INSERT INTO image VALUES ('a', 'Primary', 0, '/elsewhere.jpg', 't')`)
	old := time.Now().Add(-48 * time.Hour)
	for _, name := range []string{"a.jpg", "b.jpg", "c.jpg"} {
		p := filepath.Join(root, "metadata", name)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte("x"), 0o644)
		os.Chtimes(p, old, old)
	}
	if n, _ := SweepOrphanArt(db, root, slog.New(slog.NewTextHandler(io.Discard, nil))); n != 0 {
		t.Fatal("nothing is removed when most of the folder is unreferenced")
	}
}
