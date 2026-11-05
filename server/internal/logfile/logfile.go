// Package logfile keeps the server's log on disk, rotated.
//
// LumiereControl shows the server's recent output only while it runs, so
// what happened overnight — the backup, the shrink check, the subtitle queue —
// was gone by morning. The log is also written to logs/lumiered.log beside
// the database, rotated at 10 MB with four old copies kept: one copy was
// what a single busy day used to fill, and the night before is exactly the
// one that is wanted when something went wrong.
package logfile

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
)

const (
	limit = 10 << 20
	kept  = 4
)

type rotating struct {
	mu   sync.Mutex
	path string
	file *os.File
	size int64
}

// Tee returns a writer that sends everything to the rotating file under
// dataDir/logs and to `w`. If the file cannot be opened, `w` alone.
//
// The file first, and `w`'s errors ignored. `w` is stderr, a pipe to
// LumiereControl; when that app goes, every write to it fails, and
// io.MultiWriter stops at the first failing writer — so the file, the one
// record of why anything happened, would have gone quiet at exactly the moment
// it mattered.
func Tee(w io.Writer, dataDir string) io.Writer {
	dir := filepath.Join(dataDir, "logs")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return w
	}
	r := &rotating{path: filepath.Join(dir, "lumiered.log")}
	if err := r.open(); err != nil {
		return w
	}
	return io.MultiWriter(r, bestEffort{w})
}

// bestEffort writes and never reports failure.
type bestEffort struct{ w io.Writer }

func (b bestEffort) Write(p []byte) (int, error) {
	b.w.Write(p)
	return len(p), nil
}

func (r *rotating) open() error {
	f, err := os.OpenFile(r.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	info, _ := f.Stat()
	r.file, r.size = f, info.Size()
	return nil
}

func (r *rotating) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.size+int64(len(p)) > limit {
		r.file.Close()
		for i := kept - 1; i >= 1; i-- {
			os.Rename(fmt.Sprintf("%s.%d", r.path, i), fmt.Sprintf("%s.%d", r.path, i+1))
		}
		os.Rename(r.path, r.path+".1")
		if err := r.open(); err != nil {
			return len(p), nil // never fail the caller over its log
		}
	}
	n, err := r.file.Write(p)
	r.size += int64(n)
	return n, err
}
