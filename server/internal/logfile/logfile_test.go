package logfile

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTheLogRotatesAndKeepsOneOldCopy(t *testing.T) {
	dir := t.TempDir()
	w := Tee(io.Discard, dir)
	line := strings.Repeat("x", 1<<20) + "\n"
	for i := 0; i < 7; i++ {
		w.Write([]byte(line))
	}
	cur, err := os.Stat(filepath.Join(dir, "logs", "lumiered.log"))
	if err != nil || cur.Size() > limit {
		t.Fatalf("current log %v (%v), want under the limit", cur, err)
	}
	if _, err := os.Stat(filepath.Join(dir, "logs", "lumiered.log.1")); err != nil {
		t.Error("no rotated copy")
	}
}
