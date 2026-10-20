package safefs

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWritesStayInTheirFolder(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "media")
	os.Mkdir(root, 0o755)
	if err := WriteFile(root, filepath.Join(root, "film.en.srt"), []byte("ok"), 0o644); err != nil {
		t.Fatalf("plain write refused: %v", err)
	}
	for _, evil := range []string{
		filepath.Join(root, "film.x/../../escape.srt"),
		filepath.Join(root, "..", "escape.srt"),
		"/tmp/escape.srt",
		root,
	} {
		if err := WriteFile(root, evil, []byte("x"), 0o644); err == nil {
			t.Fatalf("wrote outside: %s", evil)
		}
	}
	// A symlinked folder pointing out, and a symlink at the final name.
	os.Symlink(dir, filepath.Join(root, "out"))
	if err := WriteFile(root, filepath.Join(root, "out", "escape.srt"), []byte("x"), 0o644); err == nil {
		t.Fatal("wrote through a symlinked folder")
	}
	os.Symlink(filepath.Join(dir, "target"), filepath.Join(root, "link.srt"))
	if err := WriteFile(root, filepath.Join(root, "link.srt"), []byte("x"), 0o644); err == nil {
		t.Fatal("wrote through a symlinked file")
	}
	if Token("../../en", 16) != "en" || Token("pt-BR", 16) != "pt-BR" {
		t.Fatal("token kept a path")
	}
}
