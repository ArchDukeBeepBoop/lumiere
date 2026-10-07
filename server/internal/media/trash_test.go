package media

import (
	"os"
	"path/filepath"
	"testing"
)

func TestTrashMovesRatherThanUnlinks(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "lumiere-trash-test.txt")
	os.WriteFile(file, []byte("x"), 0o644)
	moved, err := Trash(file)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(moved)
	if _, err := os.Stat(file); err == nil {
		t.Error("file still at its original path")
	}
	if _, err := os.Stat(moved); err != nil {
		t.Errorf("file not in the trash: %v", err)
	}
}
