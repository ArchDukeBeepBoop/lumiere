package store

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// A library that was there yesterday and is gone today is an incident, not a
// first run.
//
// On 2026-10-25 the database was deleted while the server ran, and at the next
// start the server did what it had always done with a missing file: made a new,
// empty one, under a new identity, and served it. Every app was signed out, the
// library read as empty, and nothing anywhere said why. PostgreSQL refuses to
// start on a missing data directory rather than quietly initialising one, and
// this follows it.
//
// The evidence that a library existed is kept where the thing it vouches for
// is not: a witness file outside the data folder, and the backups, which have
// their own folder. Either is enough to refuse.

// ExitLibraryMissing is the exit status for a refusal, so LumiereControl can
// offer Restore and Start Fresh rather than only an error.
const ExitLibraryMissing = 3

// Witness is what the server last knew about its library.
type Witness struct {
	ServerID string `json:"serverId"`
	Items    int    `json:"items"`
	Seen     string `json:"seen"`
}

// ReadWitness returns the witness, or a zero one when there is none.
func ReadWitness(path string) Witness {
	var w Witness
	if raw, err := os.ReadFile(path); err == nil {
		json.Unmarshal(raw, &w)
	}
	return w
}

// CheckLibraryPresent refuses a start whose database is missing while the
// witness or a backup says there was one.
func CheckLibraryPresent(dataDir, witness string, places BackupPlaces) error {
	db := filepath.Join(dataDir, "library.db")
	if _, err := os.Stat(db); err == nil {
		return nil
	}
	w := ReadWitness(witness)
	copies := len(backupNames(places.Dir))
	if places.Mirror != "" {
		copies += len(backupNames(places.Mirror))
	}
	if w.Items == 0 && copies == 0 {
		return nil // a first run
	}
	return missing(db, w, copies)
}

// CheckNotEmptied is the same refusal for a database that is there but holds
// nothing, where the witness remembers a library — the file a server older
// than this rule made in place of the one that was lost.
func (s *Store) CheckNotEmptied(dataDir, witness string) error {
	w := ReadWitness(witness)
	if w.Items == 0 || s.mediaCount() > 0 {
		return nil
	}
	return missing(filepath.Join(dataDir, "library.db"), w, 0)
}

func missing(db string, w Witness, copies int) error {
	what := "a library"
	if w.Items > 0 {
		what = fmt.Sprintf("a library of %d items", w.Items)
		if seen, err := time.Parse(time.RFC3339, w.Seen); err == nil {
			what += ", last seen " + seen.Local().Format("2 Jan 2006 15:04")
		}
	}
	return fmt.Errorf("the library database is missing (%s), but this Mac had %s and %d backup copies. "+
		"Restore a backup from the Lumiere Control menu, or choose Start Fresh", db, what, copies)
}

// RecordWitness writes what the server knows now. An empty library is not
// recorded, so a witness never forgets a library because a start went wrong.
func (s *Store) RecordWitness(path, serverID string) error {
	n := s.mediaCount()
	if n == 0 {
		return nil
	}
	raw, _ := json.Marshal(Witness{ServerID: serverID, Items: n, Seen: time.Now().UTC().Format(time.RFC3339)})
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(path+".new", raw, 0o600); err != nil {
		return err
	}
	return os.Rename(path+".new", path)
}

// ForgetWitness is Start Fresh: the one deliberate way past the refusal.
func ForgetWitness(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func (s *Store) mediaCount() int {
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE is_folder = 0`).Scan(&n)
	return n
}
