package store

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
)

func TestRelocateCacheMovesFilesAndRepointsRows(t *testing.T) {
	s := testStore(t)
	from := filepath.Join(t.TempDir(), "cache")
	to := filepath.Join(t.TempDir(), "drive", "Lumiere Pictures")
	os.MkdirAll(filepath.Join(from, "images", "frames"), 0o755)
	os.WriteFile(filepath.Join(from, "images", "frames", "a.jpg"), []byte("jpeg"), 0o644)
	os.MkdirAll(filepath.Join(from, "trickplay"), 0o755)
	os.WriteFile(filepath.Join(from, "trickplay", "x.jpg"), []byte("sheet"), 0o644)
	s.DB.Exec(`INSERT INTO image (item_id, kind, idx, path, tag) VALUES
		('a', 'Primary', 0, ?, 't'), ('b', 'Primary', 0, '/elsewhere/b.jpg', 't')`, filepath.Join(from, "images", "frames", "a.jpg"))
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	s.RelocateCache(from, to, log)

	var a, b string
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = 'a'`).Scan(&a)
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = 'b'`).Scan(&b)
	if a != filepath.Join(to, "images", "frames", "a.jpg") || b != "/elsewhere/b.jpg" {
		t.Fatalf("paths: %q %q", a, b)
	}
	if data, err := os.ReadFile(a); err != nil || string(data) != "jpeg" {
		t.Fatal("the picture is at its new place")
	}
	if _, err := os.Stat(filepath.Join(to, "trickplay", "x.jpg")); err != nil {
		t.Fatal("previews moved too")
	}
	if _, err := os.Stat(from); !os.IsNotExist(err) {
		t.Fatal("the old folder is cleared once nothing names it")
	}
	if s.CacheRoot("x") != to {
		t.Fatal("the new root is remembered")
	}
}

func TestRelocateCacheWaitsForAnUnpluggedDrive(t *testing.T) {
	s := testStore(t)
	s.RelocateCache("/Volumes/Not Plugged In/cache", t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	if s.CacheRoot("unchanged") != "unchanged" {
		t.Fatal("a move from a drive that is not there waits; nothing is recorded")
	}
}
