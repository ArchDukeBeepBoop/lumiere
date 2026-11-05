package store

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestBackupWritesAReadableCopyAndPrunesTheOldest(t *testing.T) {
	s := testStore(t)
	dir := filepath.Join(t.TempDir(), "backups")
	if _, err := s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('x', 'Movie', 'Kept', 0)`); err != nil {
		t.Fatal(err)
	}
	// Ten old copies on ten consecutive days, named so they sort first.
	os.MkdirAll(dir, 0o700)
	for i := 1; i <= 10; i++ {
		os.WriteFile(filepath.Join(dir, fmt.Sprintf("library-200003%02d-000000.db", i)), nil, 0o600)
	}
	path, err := s.Backup(dir)
	if err != nil {
		t.Fatal(err)
	}
	copyStore, err := Open(filepath.Join(t.TempDir(), "restore"))
	if err != nil {
		t.Fatal(err)
	}
	copyStore.Close()
	if info, err := os.Stat(path); err != nil || info.Size() == 0 {
		t.Fatalf("backup missing or empty: %v", err)
	}
	// The new one and the six newest days. The four oldest share a week with
	// the 5th, which is already kept, so the weekly rule adds nothing here.
	names := backupNames(dir)
	if len(names) != BackupsKept {
		t.Errorf("%d copies kept, want %d: %v", len(names), BackupsKept, names)
	}
	if names[len(names)-1] != filepath.Base(path) {
		t.Error("the new copy was pruned instead of an old one")
	}
}

func TestRetentionKeepsAWeekOfDailiesAndTwoMonthsOfWeeklies(t *testing.T) {
	var names []string
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	for d := 0; d < 120; d++ {
		names = append(names, "library-"+start.AddDate(0, 0, d).Format("20060102")+"-030000.db")
	}
	keep := retained(names)
	// The last day is Thursday 30 April, so the seven dailies reach back into
	// the week before, and both weeks' newest copies are dailies already.
	if len(keep) != BackupsKept+WeeksKept-2 {
		t.Errorf("%d kept, want %d", len(keep), BackupsKept+WeeksKept-2)
	}
	for _, n := range names[len(names)-BackupsKept:] {
		if !keep[n] {
			t.Errorf("recent daily %s pruned", n)
		}
	}
	if keep[names[0]] {
		t.Error("a four-month-old copy survived")
	}
}

func TestOldBackupsMoveOutOfTheDataFolder(t *testing.T) {
	data, dir := t.TempDir(), filepath.Join(t.TempDir(), "LumiereServer Backups")
	os.MkdirAll(filepath.Join(data, "backups"), 0o700)
	os.WriteFile(filepath.Join(data, "backups", "library-20261020-030000.db"), []byte("x"), 0o600)
	if n, err := MoveOldBackups(data, dir); err != nil || n != 1 {
		t.Fatalf("moved %d: %v", n, err)
	}
	if len(backupNames(dir)) != 1 || len(backupNames(filepath.Join(data, "backups"))) != 0 {
		t.Error("the copy did not move")
	}
	if _, err := os.Stat(filepath.Join(data, "backups")); !os.IsNotExist(err) {
		t.Error("the emptied old folder was left behind")
	}
}

func TestAMirrorThatIsNotAttachedIsRefusedNotCreated(t *testing.T) {
	s := testStore(t)
	path, err := s.Backup(filepath.Join(t.TempDir(), "b"))
	if err != nil {
		t.Fatal(err)
	}
	gone := filepath.Join(t.TempDir(), "unplugged")
	if Mirror(path, gone) == nil {
		t.Error("a missing second folder was accepted")
	}
	if _, err := os.Stat(gone); !os.IsNotExist(err) {
		t.Error("a folder was made where a disk should have been")
	}
	there := t.TempDir()
	if err := Mirror(path, there); err != nil || len(backupNames(there)) != 1 {
		t.Errorf("mirror: %v", err)
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
	dir := filepath.Join(t.TempDir(), "backups")
	if _, err := s.Backup(dir); err != nil {
		t.Fatal(err)
	}
	if problem := s.RehearseRestore(dir); problem != "" {
		t.Fatalf("a good backup failed its rehearsal: %s", problem)
	}
	// A newer copy that is not a database at all.
	os.WriteFile(filepath.Join(dir, "library-29990101-000000.db"), []byte("garbage"), 0o600)
	if problem := s.RehearseRestore(dir); problem == "" {
		t.Error("a broken newest backup passed its rehearsal")
	}
}
