package store

import (
	"os"
	"path/filepath"
	"testing"
)

func TestBackupWritesAReadableCopyAndKeepsOnlyTheNewest(t *testing.T) {
	s := testStore(t)
	dir := t.TempDir()
	if _, err := s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('x', 'Movie', 'Kept', 0)`); err != nil {
		t.Fatal(err)
	}
	// Old copies already there, named so they sort first.
	os.MkdirAll(filepath.Join(dir, "backups"), 0o700)
	for i := 0; i < BackupsKept+2; i++ {
		os.WriteFile(filepath.Join(dir, "backups", "library-2000010"+string(rune('0'+i))+"-000000.db"), nil, 0o600)
	}
	path, err := s.Backup(dir)
	if err != nil {
		t.Fatal(err)
	}
	copyStore, err := Open(filepath.Dir(path) + "/restore")
	if err != nil {
		t.Fatal(err)
	}
	copyStore.Close()
	info, err := os.Stat(path)
	if err != nil || info.Size() == 0 {
		t.Fatalf("backup missing or empty: %v", err)
	}
	entries, _ := os.ReadDir(filepath.Join(dir, "backups"))
	dbs := 0
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".db" {
			dbs++
		}
	}
	if dbs != BackupsKept {
		t.Errorf("%d copies kept, want %d", dbs, BackupsKept)
	}
	if _, err := os.Stat(path); err != nil {
		t.Error("the new copy was pruned instead of an old one")
	}
}

func TestADamagedCopyFailsItsCheck(t *testing.T) {
	path := filepath.Join(t.TempDir(), "library-bad.db")
	if err := os.WriteFile(path, []byte("not a database at all"), 0o600); err != nil {
		t.Fatal(err)
	}
	if verifyBackup(path) == nil {
		t.Error("a file that is not a database passed the check")
	}
}

func TestARestoreRehearsalPassesOnAGoodCopyAndFailsOnABadOne(t *testing.T) {
	s := testStore(t)
	dir := t.TempDir()
	if _, err := s.Backup(dir); err != nil {
		t.Fatal(err)
	}
	if problem := s.RehearseRestore(dir); problem != "" {
		t.Fatalf("a good backup failed its rehearsal: %s", problem)
	}
	// A newer copy that is not a database at all.
	os.WriteFile(filepath.Join(dir, "backups", "library-29990101-000000.db"), []byte("garbage"), 0o600)
	if problem := s.RehearseRestore(dir); problem == "" {
		t.Error("a broken newest backup passed its rehearsal")
	}
}
