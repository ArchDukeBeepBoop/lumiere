package logfile

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTheLogRotatesAndKeepsFourOldCopies(t *testing.T) {
	dir := t.TempDir()
	w := Tee(io.Discard, dir)
	line := strings.Repeat("x", 1<<20) + "\n"
	for i := 0; i < 70; i++ {
		w.Write([]byte(line))
	}
	cur, err := os.Stat(filepath.Join(dir, "logs", "lumiered.log"))
	if err != nil || cur.Size() > limit {
		t.Fatalf("current log %v (%v), want under the limit", cur, err)
	}
	for _, n := range []string{"1", "2", "3", "4"} {
		if _, err := os.Stat(filepath.Join(dir, "logs", "lumiered.log."+n)); err != nil {
			t.Errorf("no rotated copy %s", n)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "logs", "lumiered.log.5")); err == nil {
		t.Error("a fifth old copy was kept")
	}
}

type brokenPipe struct{}

func (brokenPipe) Write(p []byte) (int, error) { return 0, os.ErrClosed }

func TestTheFileKeepsLoggingWhenStderrIsGone(t *testing.T) {
	dir := t.TempDir()
	w := Tee(brokenPipe{}, dir)
	if _, err := w.Write([]byte("after the controller went\n")); err != nil {
		t.Fatalf("a dead stderr failed the write: %v", err)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "logs", "lumiered.log"))
	if !strings.Contains(string(got), "after the controller went") {
		t.Error("the line never reached the file")
	}
}
