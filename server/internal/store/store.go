// Package store is this server's own database: SQLite, raw SQL, no ORM.
package store

import (
	"database/sql"
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"
)

//go:embed schema.sql
var schema string

type Store struct {
	DB *sql.DB
}

// Open creates the database if it is not there and applies the schema.
//
// Pragmas are set once, on the connection string: WAL so a long import cannot
// block a read, and a busy timeout because the import and the server may
// legitimately want the file at the same moment.
func Open(dataDir string) (*Store, error) {
	// 0700, not 0755. This directory holds library.db, and library.db holds
	// live session tokens — a token is valid until the server rejects it, and
	// nothing here expires one. World-readable was enough for any other account
	// on this Mac to lift one and be indistinguishable from the owner.
	//
	// The directory mode is what does the work: a 0700 directory cannot be
	// walked into, whatever the modes of the files inside it, and SQLite creates
	// its -wal and -shm siblings on its own terms.
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return nil, fmt.Errorf("data directory: %w", err)
	}
	path := filepath.Join(dataDir, "library.db")

	// A 60-second busy timeout, up from 5. The scanner holds a write transaction
	// for stretches measured at 15 seconds, roughly a third of the time, and any
	// second process — the menu's Import or Push — that opened during one hit
	// SQLITE_BUSY on the first repair pass and refused to start. Sixty seconds
	// is longer than any transaction here has a right to be; if a wait ever
	// reaches it, the scanner is the thing to look at, not this number.
	db, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(60000)&_pragma=foreign_keys(on)")
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	if err := applySchema(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := ensureChangeLog(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := onePerFile(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := hashStoredTokens(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := clearZeroIDs(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := LinkEpisodes(db); err != nil {
		db.Close()
		return nil, err
	}
	if _, err := NumberEpisodes(db); err != nil {
		db.Close()
		return nil, err
	}
	// Existing installs were created 0755 and would otherwise stay that way.
	if err := os.Chmod(dataDir, 0o700); err != nil {
		return nil, err
	}
	return &Store{DB: db}, nil
}

func (s *Store) Close() error { return s.DB.Close() }

// Count is for the import's own acceptance check: the numbers it reports are
// the ones compared against Jellyfin's.
func (s *Store) Count(table string) (int, error) {
	var n int
	// The table name cannot be a placeholder, and it never comes from input —
	// every caller passes a literal.
	err := s.DB.QueryRow("SELECT count(*) FROM " + table).Scan(&n)
	return n, err
}

// applySchema runs schema.sql, tolerating the statements that are only new the
// first time.
//
// SQLite has no ADD COLUMN IF NOT EXISTS, and the alternative — a migration
// table and a version number — is more machinery than a server with one
// deployment needs. So an ALTER that fails because the column is already there
// is not an error; anything else still is. The distinction is made on the
// message because SQLite offers nothing better.
func applySchema(db *sql.DB) error {
	// Comments are stripped before the split, not after. A comment containing a
	// semicolon — and one here does — otherwise splits into two fragments, the
	// second of which is prose that SQLite is then asked to execute.
	for _, stmt := range strings.Split(stripComments(schema), ";") {
		if strings.TrimSpace(stmt) == "" {
			continue
		}
		if _, err := db.Exec(stmt); err != nil {
			if strings.Contains(err.Error(), "duplicate column name") {
				continue
			}
			return fmt.Errorf("apply schema: %w", err)
		}
	}
	return nil
}

// hashStoredTokens converts any token still stored in the clear.
//
// Idempotent, and identified by shape rather than by a version number — which
// is the same bargain `applySchema` already makes for a server with one
// deployment. A hash is 64 hex characters and a token is 32, so a row that is
// not 64 long has never been through this.
//
// In place rather than by invalidating them, and that is the whole point of
// doing it this way: hashing what is there keeps every signed-in client signed
// in. Deleting the table would have been one line and would have logged the
// owner out of the app they were using at the time.
func hashStoredTokens(db *sql.DB) error {
	rows, err := db.Query(`SELECT token FROM token WHERE length(token) <> 64`)
	if err != nil {
		return fmt.Errorf("read tokens: %w", err)
	}
	var plain []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			rows.Close()
			return err
		}
		plain = append(plain, t)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, t := range plain {
		if _, err := db.Exec(
			`UPDATE token SET token = ? WHERE token = ?`, HashToken(t), t,
		); err != nil {
			return fmt.Errorf("hash stored token: %w", err)
		}
	}
	return nil
}

// stripComments removes SQL line comments so a statement that is nothing but
// commentary is recognised as empty.
func stripComments(stmt string) string {
	var out []string
	for _, line := range strings.Split(stmt, "\n") {
		if i := strings.Index(line, "--"); i >= 0 {
			line = line[:i]
		}
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}

// clearZeroIDs turns Jellyfin's all-zero GUID into an actual absence.
//
// Idempotent and identified by shape, like hashStoredTokens above: rows already
// clean match nothing. NormalizeID rejects the value now, so nothing new can
// arrive carrying it, but 425 episodes were imported before it did — each one a
// child of an id no row has, and so missing from its own series page.
//
// NULL rather than the empty string because that is what every other "no
// parent" row in this table holds, and two spellings of absent is how a query
// comes to be right about half its rows.
func clearZeroIDs(db *sql.DB) error {
	for _, column := range []string{"season_id", "parent_id", "series_id"} {
		if _, err := db.Exec(
			`UPDATE item SET `+column+` = NULL WHERE `+column+` = ?`, ZeroGUID,
		); err != nil {
			return fmt.Errorf("clear zero %s: %w", column, err)
		}
	}
	return nil
}
