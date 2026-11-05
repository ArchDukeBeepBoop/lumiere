package media

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCoverInFolderPrefersNamedCovers(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"01 Song.mp3", "back.jpg", "Folder.JPG"} {
		os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o644)
	}
	if got := filepath.Base(CoverInFolder(dir)); got != "Folder.JPG" {
		t.Fatalf("named cover should win, got %q", got)
	}
	lone := t.TempDir()
	os.WriteFile(filepath.Join(lone, "scan.png"), []byte("x"), 0o644)
	if got := filepath.Base(CoverInFolder(lone)); got != "scan.png" {
		t.Fatalf("a lone picture is the cover, got %q", got)
	}
	none := t.TempDir()
	os.WriteFile(filepath.Join(none, "a.jpg"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(none, "b.jpg"), []byte("x"), 0o644)
	if got := CoverInFolder(none); got != "" {
		t.Fatalf("two unnamed pictures are not a choice to guess, got %q", got)
	}
}
