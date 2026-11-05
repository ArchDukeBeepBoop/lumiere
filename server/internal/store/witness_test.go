package store

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAFirstRunStarts(t *testing.T) {
	root := t.TempDir()
	places := BackupPlaces{Dir: filepath.Join(root, "backups")}
	if err := CheckLibraryPresent(filepath.Join(root, "data"), filepath.Join(root, "witness"), places); err != nil {
		t.Fatalf("a Mac with no library, no witness and no backups refused: %v", err)
	}
}

func TestAMissingLibraryIsRefusedWhenTheWitnessRemembersIt(t *testing.T) {
	root := t.TempDir()
	data, witness := filepath.Join(root, "data"), filepath.Join(root, "Preferences", "witness")
	places := BackupPlaces{Dir: filepath.Join(root, "backups")}
	s, err := Open(data)
	if err != nil {
		t.Fatal(err)
	}
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, path) VALUES ('a', 'Movie', 'A', 0, '/a.mkv'), ('b', 'Movie', 'B', 0, '/b.mkv')`)
	if err := s.RecordWitness(witness, "server"); err != nil {
		t.Fatal(err)
	}
	if err := CheckLibraryPresent(data, witness, places); err != nil {
		t.Fatalf("a library that is there was refused: %v", err)
	}
	s.Close()

	// What the disk cleaner did.
	for _, f := range []string{"library.db", "library.db-wal", "library.db-shm"} {
		os.Remove(filepath.Join(data, f))
	}
	err = CheckLibraryPresent(data, witness, places)
	if err == nil || !strings.Contains(err.Error(), "2 items") {
		t.Fatalf("a deleted library was not refused, or the reason left out its size: %v", err)
	}

	// Start Fresh is the way through.
	if err := ForgetWitness(witness); err != nil {
		t.Fatal(err)
	}
	if err := CheckLibraryPresent(data, witness, places); err != nil {
		t.Errorf("Start Fresh did not clear the refusal: %v", err)
	}
}

func TestBackupsAloneAreEvidenceOfALibrary(t *testing.T) {
	root := t.TempDir()
	places := BackupPlaces{Dir: filepath.Join(root, "backups")}
	os.MkdirAll(places.Dir, 0o700)
	os.WriteFile(filepath.Join(places.Dir, "library-20261024-030000.db"), []byte("x"), 0o600)
	if CheckLibraryPresent(filepath.Join(root, "data"), filepath.Join(root, "witness"), places) == nil {
		t.Error("backups with no database were treated as a first run")
	}
}

func TestAnEmptiedDatabaseIsRefusedAndNeverRecorded(t *testing.T) {
	root := t.TempDir()
	witness := filepath.Join(root, "witness")
	full := testStore(t)
	full.DB.Exec(`INSERT INTO item (id, type, name, is_folder, path) VALUES ('a', 'Movie', 'A', 0, '/a.mkv')`)
	full.RecordWitness(witness, "server")

	empty := testStore(t)
	if err := empty.CheckNotEmptied(root, witness); err == nil {
		t.Error("an empty database was served where the witness remembers a library")
	}
	empty.RecordWitness(witness, "other")
	if w := ReadWitness(witness); w.Items != 1 || w.ServerID != "server" {
		t.Errorf("an empty start overwrote the witness: %+v", w)
	}
	if err := full.CheckNotEmptied(root, witness); err != nil {
		t.Errorf("a full library was refused: %v", err)
	}
}
