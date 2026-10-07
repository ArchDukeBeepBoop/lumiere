package media

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPruningNeverTouchesOriginals(t *testing.T) {
	dir := t.TempDir()
	write := func(rel string, size int) string {
		p := filepath.Join(dir, rel)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, make([]byte, size), 0o644)
		return p
	}
	frame := write("frames/a.jpg", 4000)
	art := write("metadata/b-primary.jpg", 4000)
	mosaic := write("c-mosaic.jpg", 4000)
	variant := write("0f/old.jpg", 4000)
	if err := pruneDir(dir, 1000); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{frame, art, mosaic} {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("an original was deleted: %s", p)
		}
	}
	if _, err := os.Stat(variant); err == nil {
		t.Error("the variant over the cap should have gone")
	}
}
