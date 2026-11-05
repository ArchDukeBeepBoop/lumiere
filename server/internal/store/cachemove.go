package store

import (
	"io"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// Moving the pictures and previews to the folder chosen for them.
//
// Copied first, while the server keeps serving from where they are; then the
// database's paths are repointed in one transaction; only then is the old
// folder cleared, and only if no row still names it. A move cut short — the
// drive pulled half-way — leaves everything where it was, and the next start
// carries on from what was already copied.

const metaCacheRoot = "cache_root"

var relocating sync.Mutex

// CacheRoot is the folder the database's pictures were last moved to, or
// fallback when they never have been.
func (s *Store) CacheRoot(fallback string) string {
	if v, _ := s.Meta(metaCacheRoot); v != "" {
		return v
	}
	return fallback
}

// RelocateCache moves everything kept under from to to.
func (s *Store) RelocateCache(from, to string, log *slog.Logger) {
	if !relocating.TryLock() {
		return
	}
	defer relocating.Unlock()
	from, to = filepath.Clean(from), filepath.Clean(to)
	if from == to || strings.HasPrefix(to, from+string(filepath.Separator)) {
		return
	}
	if _, err := os.Stat(from); err != nil {
		// Nothing there to bring — or its drive is not attached, in which
		// case the move waits for the next start with it plugged in.
		if os.IsNotExist(err) && !strings.HasPrefix(from, "/Volumes/") {
			s.SetMeta(metaCacheRoot, to)
		}
		return
	}
	log.Info("moving pictures and previews to the chosen folder", "from", from, "to", to)
	copied, err := copyTree(from, to)
	if err != nil {
		log.Warn("moving pictures stopped; nothing changed, it carries on at the next start", "error", err)
		return
	}
	tx, err := s.DB.Begin()
	if err != nil {
		return
	}
	defer tx.Rollback()
	res, err := tx.Exec(`UPDATE image SET path = ? || substr(path, ?) WHERE path LIKE ? ESCAPE '\'`,
		to, len(from)+1, likeEscape(from)+"/%")
	if err != nil {
		log.Warn("repointing pictures failed; nothing changed", "error", err)
		return
	}
	if _, err := tx.Exec(`INSERT INTO meta (key, value) VALUES (?, ?)
		ON CONFLICT(key) DO UPDATE SET value = excluded.value`, metaCacheRoot, to); err != nil {
		return
	}
	if tx.Commit() != nil {
		return
	}
	rows, _ := res.RowsAffected()
	var left int
	s.DB.QueryRow(`SELECT count(*) FROM image WHERE path LIKE ? ESCAPE '\'`, likeEscape(from)+"/%").Scan(&left)
	if left == 0 {
		os.RemoveAll(from)
	}
	log.Info("pictures and previews moved", "files", copied, "pictures", rows, "to", to, "old folder cleared", left == 0)
}

// copyTree copies every file under from into to, skipping any already there
// at the same size; returns how many it copied.
func copyTree(from, to string) (int, error) {
	n := 0
	err := filepath.WalkDir(from, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(from, path)
		dest := filepath.Join(to, rel)
		if d.IsDir() {
			return os.MkdirAll(dest, 0o755)
		}
		if !d.Type().IsRegular() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if have, err := os.Stat(dest); err == nil && have.Size() == info.Size() {
			return nil
		}
		if err := copyCacheFile(path, dest); err != nil {
			return err
		}
		n++
		return nil
	})
	return n, err
}

func copyCacheFile(from, to string) error {
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := to + ".part"
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, to)
}
