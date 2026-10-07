package store

import (
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Rolling backups of the database.
//
// library.db holds the one thing that cannot be rebuilt from the disk: what
// has been watched, and where each file was stopped. Everything else is a
// rescan away. So a copy is taken at start and once a day after, into
// backups/ beside the database, and the newest few are kept.
//
// VACUUM INTO rather than a file copy: it writes a consistent snapshot while
// the server keeps serving, and the copy comes out compacted.

// BackupsKept is how many daily copies survive. A week covers "it was right
// on Sunday" without the folder growing past a few gigabytes.
const BackupsKept = 7

// Backup writes one snapshot and prunes the oldest beyond BackupsKept.
func (s *Store) Backup(dataDir string) (string, error) {
	dir := filepath.Join(dataDir, "backups")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "library-"+time.Now().Format("20060102-150405")+".db")
	if _, err := s.DB.Exec(`VACUUM INTO ?`, path); err != nil {
		return "", fmt.Errorf("backup: %w", err)
	}
	// Checked before it counts. A copy that will not open is found out on the
	// day it is needed, and pruning would already have deleted the good ones
	// to make room for it.
	if err := verifyBackup(path); err != nil {
		os.Remove(path)
		return "", fmt.Errorf("backup failed its check and was discarded: %w", err)
	}
	return path, pruneBackups(dir, BackupsKept)
}

func pruneBackups(dir string, keep int) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	var names []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "library-") && strings.HasSuffix(e.Name(), ".db") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names) // the timestamp sorts oldest first
	for len(names) > keep {
		if err := os.Remove(filepath.Join(dir, names[0])); err != nil {
			return err
		}
		names = names[1:]
	}
	return nil
}

// KeepBackedUp takes a backup now and every day after, for the life of the
// process. A failure is logged, never fatal: a server that stops serving
// because it could not copy itself protects nothing.
func (s *Store) KeepBackedUp(dataDir string, log *slog.Logger) {
	go func() {
		for {
			if age := newestBackupAge(dataDir); age < 20*time.Hour {
				// A restart, not a new day: the copy from this morning stands.
				time.Sleep(24*time.Hour - age)
				continue
			}
			if path, err := s.Backup(dataDir); err != nil {
				log.Error("backup failed", "error", err)
			} else {
				log.Info("backup written", "path", path)
				// Then the night-on-night comparison. See drift.go.
				if warning, err := s.CheckDrift(); err == nil && warning != "" {
					log.Warn("library shrank overnight", "detail", warning)
				}
				// Last night's findings, for "since yesterday". See health_since.go.
				s.SnapshotHealth()
				// And once a week, a rehearsed restore. See restorecheck.go.
				if ran, problem := s.RehearseWeekly(dataDir); ran && problem != "" {
					log.Warn("the newest backup could not be restored", "detail", problem)
				} else if ran {
					log.Info("restore rehearsal passed")
				}
			}
			time.Sleep(24 * time.Hour)
		}
	}()
}

// newestBackupAge is how long ago the last copy was taken; a very long time
// when there is none.
func newestBackupAge(dataDir string) time.Duration {
	entries, err := os.ReadDir(filepath.Join(dataDir, "backups"))
	newest := time.Duration(1 << 62)
	if err != nil {
		return newest
	}
	for _, e := range entries {
		if info, err := e.Info(); err == nil && strings.HasSuffix(e.Name(), ".db") {
			newest = min(newest, time.Since(info.ModTime()))
		}
	}
	return newest
}

// verifyBackup opens a copy read-only and asks SQLite whether it is whole.
func verifyBackup(path string) error {
	db, err := sql.Open("sqlite", "file:"+path+"?mode=ro")
	if err != nil {
		return err
	}
	defer db.Close()
	var result string
	if err := db.QueryRow(`PRAGMA quick_check`).Scan(&result); err != nil {
		return err
	}
	if result != "ok" {
		return fmt.Errorf("quick_check: %s", result)
	}
	return nil
}
