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
// rescan away. So a copy is taken at start and once a day after.
//
// Not beside the database. On 2026-10-25 a disk cleaner emptied the data
// folder and the week of copies went with it — every one verified, every one
// in the same place as the thing it protected. The 3-2-1 rule exists for
// exactly that: the copies live in their own folder, and optionally a second
// one on another disk.
//
// VACUUM INTO rather than a file copy: it writes a consistent snapshot while
// the server keeps serving, and the copy comes out compacted.

// BackupsKept is how many daily copies survive; WeeksKept how many weeks keep
// one copy each beyond them. A week covers "it was right on Sunday"; two months
// covers a loss nobody noticed for a while.
const (
	BackupsKept = 7
	WeeksKept   = 8
)

// BackupPlaces are where copies go. Mirror is optional, and may be a disk that
// is not always attached: a missing mirror is a warning, never a failed backup.
type BackupPlaces struct {
	Dir, Mirror string
}

// Backup writes one snapshot into dir and prunes it.
func (s *Store) Backup(dir string) (string, error) {
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
	return path, pruneBackups(dir)
}

// Mirror copies a verified backup into the second place and prunes it there.
func Mirror(path, dir string) error {
	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		return fmt.Errorf("the second backup folder is not there: %s", dir)
	}
	to := filepath.Join(dir, filepath.Base(path))
	if err := copyFile(path, to+".partial"); err != nil {
		os.Remove(to + ".partial")
		return err
	}
	// Renamed into place only once whole, so a disk pulled out mid-copy never
	// leaves a file that looks like a backup and is not one.
	if err := os.Rename(to+".partial", to); err != nil {
		return err
	}
	return pruneBackups(dir)
}

func backupNames(dir string) []string {
	entries, _ := os.ReadDir(dir)
	var names []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "library-") && strings.HasSuffix(e.Name(), ".db") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names) // the timestamp sorts oldest first
	return names
}

func pruneBackups(dir string) error {
	keep := retained(backupNames(dir))
	for _, name := range backupNames(dir) {
		if !keep[name] {
			if err := os.Remove(filepath.Join(dir, name)); err != nil {
				return err
			}
		}
	}
	return nil
}

// retained is which copies survive: the newest BackupsKept, and the newest of
// each of the last WeeksKept weeks that has one. Names are library-YYYYMMDD-…,
// oldest first. Pure.
func retained(names []string) map[string]bool {
	keep := map[string]bool{}
	for i := len(names) - 1; i >= 0 && len(names)-i <= BackupsKept; i-- {
		keep[names[i]] = true
	}
	weeks := map[string]bool{}
	for i := len(names) - 1; i >= 0 && len(weeks) < WeeksKept; i-- {
		stamp := strings.TrimPrefix(names[i], "library-")
		if len(stamp) < 8 {
			continue
		}
		day, err := time.Parse("20060102", stamp[:8])
		if err != nil {
			continue
		}
		year, week := day.ISOWeek()
		key := fmt.Sprint(year, week)
		if !weeks[key] {
			weeks[key] = true
			keep[names[i]] = true
		}
	}
	return keep
}

// MoveOldBackups brings copies from the folder they used to share with the
// database into their own, once. Moved rather than copied: two sets would be
// pruned separately and drift.
func MoveOldBackups(dataDir, dir string) (int, error) {
	old := filepath.Join(dataDir, "backups")
	names := backupNames(old)
	if len(names) == 0 {
		return 0, nil
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return 0, err
	}
	moved := 0
	for _, name := range names {
		if err := os.Rename(filepath.Join(old, name), filepath.Join(dir, name)); err != nil {
			return moved, err
		}
		moved++
	}
	os.Remove(old) // only if now empty
	return moved, nil
}

// KeepBackedUp takes a backup now and every day after, for the life of the
// process. A failure is logged, never fatal: a server that stops serving
// because it could not copy itself protects nothing.
func (s *Store) KeepBackedUp(places BackupPlaces, log *slog.Logger) {
	go func() {
		for {
			if age := newestBackupAge(places.Dir); age < 20*time.Hour {
				// A restart, not a new day: the copy from this morning stands.
				time.Sleep(24*time.Hour - age)
				continue
			}
			if path, err := s.Backup(places.Dir); err != nil {
				log.Error("backup failed", "error", err)
			} else {
				log.Info("backup written", "path", path)
				// The collections too, readable on their own. See
				// collections_export.go.
				for _, dir := range []string{places.Dir, places.Mirror} {
					// A mirror on a drive that is not attached is skipped:
					// creating its folder would make one under /Volumes.
					if _, err := os.Stat(filepath.Dir(dir)); dir == "" || err != nil {
						continue
					}
					if _, err := s.WriteCollectionsExport(dir); err != nil {
						log.Warn("collections not written beside the backup", "folder", dir, "error", err)
					}
				}
				if places.Mirror != "" {
					if err := Mirror(path, places.Mirror); err != nil {
						log.Warn("second backup copy skipped", "error", err)
					} else {
						log.Info("second backup copy written", "folder", places.Mirror)
					}
				}
				// Then the night-on-night comparison. See drift.go.
				if warning, err := s.CheckDrift(); err == nil && warning != "" {
					log.Warn("library shrank overnight", "detail", warning)
				}
				// Last night's findings, for "since yesterday". See health_since.go.
				s.SnapshotHealth()
				// And once a week, a rehearsed restore. See restorecheck.go.
				if ran, problem := s.RehearseWeekly(places.Dir); ran && problem != "" {
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
func newestBackupAge(dir string) time.Duration {
	entries, err := os.ReadDir(dir)
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
