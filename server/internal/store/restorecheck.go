package store

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// A weekly rehearsal of restoring a backup.
//
// quick_check proves a copy is intact; it does not prove the server could
// start on it. Once a week the newest copy is opened the way a restore would
// open it — schema, repairs, the lot — in a scratch folder, and asked for its
// health. A copy that cannot survive that is raised in Library Health, while
// there are still good ones to fall back on.

const (
	metaRestoreCheck  = "restore_check_at"
	metaRestoreFailed = "restore_check_failed"
)

// RehearseRestore opens the newest backup in a scratch folder. It returns
// the problem, or "" when the copy opened and answered.
func (s *Store) RehearseRestore(dataDir string) string {
	newest := newestBackup(filepath.Join(dataDir, "backups"))
	if newest == "" {
		return ""
	}
	scratch, err := os.MkdirTemp("", "lumiere-restore-check-")
	if err != nil {
		return err.Error()
	}
	defer os.RemoveAll(scratch)
	if err := copyFile(newest, filepath.Join(scratch, "library.db")); err != nil {
		return "could not copy the backup: " + err.Error()
	}
	restored, err := Open(scratch)
	if err != nil {
		return fmt.Sprintf("%s would not open: %v", filepath.Base(newest), err)
	}
	defer restored.Close()
	if _, err := restored.Health(); err != nil {
		return fmt.Sprintf("%s opened but could not be read: %v", filepath.Base(newest), err)
	}
	return ""
}

// RehearseWeekly runs RehearseRestore when a week has passed since the last.
func (s *Store) RehearseWeekly(dataDir string) (ran bool, problem string) {
	last, _ := s.Meta(metaRestoreCheck)
	if when, err := time.Parse(time.RFC3339, last); err == nil && time.Since(when) < 7*24*time.Hour {
		return false, ""
	}
	problem = s.RehearseRestore(dataDir)
	s.SetMeta(metaRestoreCheck, time.Now().UTC().Format(time.RFC3339))
	s.SetMeta(metaRestoreFailed, problem)
	return true, problem
}

func (s *Store) restoreIssue() HealthIssue {
	issue := HealthIssue{Kind: "BackupUnusable", Samples: []HealthSample{}}
	if problem, _ := s.Meta(metaRestoreFailed); problem != "" {
		issue.Count = 1
		issue.Samples = append(issue.Samples, HealthSample{ID: "backup", Name: problem})
	}
	return issue
}

func newestBackup(dir string) string {
	entries, _ := os.ReadDir(dir)
	newest := ""
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".db" && e.Name() > filepath.Base(newest) {
			newest = filepath.Join(dir, e.Name())
		}
	}
	return newest
}

func copyFile(from, to string) error {
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(to)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
