package scanner

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
)

func TestPicturesWhoseFilesAreGoneAreDropped(t *testing.T) {
	s := testScanner(t)
	dir := t.TempDir()
	here := filepath.Join(dir, "here.jpg")
	os.WriteFile(here, []byte("x"), 0o644)
	db := s.Store.DB
	// Twenty pictures present and one gone: below the unplugged-drive guard.
	for i := 0; i < 20; i++ {
		db.Exec(`INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?, 'Primary', 0, ?, 't')`, "ok"+string(rune('a'+i)), here)
	}
	db.Exec(`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('lost', 'Primary', 0, ?, 't')`, filepath.Join(dir, "gone.jpg"))
	n, err := dropGoneImages(db, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil || n != 1 {
		t.Fatalf("dropped %d (%v), want 1", n, err)
	}
}
