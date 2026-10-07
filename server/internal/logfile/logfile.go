// Package logfile keeps the server's log on disk, rotated.
//
// LumiereControl shows the server's recent output only while it runs, so
// what happened overnight — the backup, the shrink check, the subtitle queue —
// was gone by morning. The log is also written to logs/lumiered.log beside
// the database, rotated at 5 MB with one old copy kept.
package logfile

import (
	"io"
	"os"
	"path/filepath"
	"sync"
)

const limit = 5 << 20

type rotating struct {
	mu   sync.Mutex
	path string
	file *os.File
	size int64
}

// Tee returns a writer that sends everything to `w` and to the rotating file
// under dataDir/logs. If the file cannot be opened, `w` alone.
func Tee(w io.Writer, dataDir string) io.Writer {
	dir := filepath.Join(dataDir, "logs")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return w
	}
	r := &rotating{path: filepath.Join(dir, "lumiered.log")}
	if err := r.open(); err != nil {
		return w
	}
	return io.MultiWriter(w, r)
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
		os.Rename(r.path, r.path+".1")
		if err := r.open(); err != nil {
			return len(p), nil // never fail the caller over its log
		}
	}
	n, err := r.file.Write(p)
	r.size += int64(n)
	return n, err
}
