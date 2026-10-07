package media

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPruneDirEvictsOldestFirst(t *testing.T) {
	dir := t.TempDir()
	// Ten 1 KB files, each a minute older than the last.
	for i := 0; i < 10; i++ {
		p := filepath.Join(dir, "ab", "cd", string(rune('a'+i))+".jpg")
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, make([]byte, 1024), 0o644); err != nil {
			t.Fatal(err)
		}
		age := time.Now().Add(-time.Duration(10-i) * time.Minute)
		if err := os.Chtimes(p, age, age); err != nil {
			t.Fatal(err)
		}
	}

	// Cap at 5 KB; the sweep goes to 80% of that, so four files should survive.
	if err := pruneDir(dir, 5*1024); err != nil {
		t.Fatal(err)
	}

	var left []string
	filepath.Walk(dir, func(p string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			left = append(left, filepath.Base(p))
		}
		return nil
	})
	if len(left) != 4 {
		t.Fatalf("kept %d files, want 4: %v", len(left), left)
	}
	// The survivors must be the newest — g, h, i, j — not the oldest.
	for _, name := range left {
		if name < "g.jpg" {
			t.Errorf("kept %s, which is older than an evicted file", name)
		}
	}
}

func TestPruneDirLeavesASmallCacheAlone(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "x.jpg")
	os.WriteFile(p, make([]byte, 100), 0o644)
	if err := pruneDir(dir, 1<<20); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(p); err != nil {
		t.Fatal("evicted from a cache that was under the cap")
	}
}
