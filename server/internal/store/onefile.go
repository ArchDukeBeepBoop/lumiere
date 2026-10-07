package store

import (
	"database/sql"
	"fmt"
)

// onePerFile makes "one file, one item" a rule the database keeps, rather
// than one that is mended after the fact.
//
// Twins — the scanner's row and the import's row for the same file — were
// found and folded by MergeTwins after every pass, and each time one slipped
// through the home screen showed an episode twice until the next pass. A
// unique index turns the second insert into a no-op instead: both inserters
// say ON CONFLICT DO NOTHING, so a file that already has a row simply keeps
// it.
//
// Folders are exempt (a series and its folder can share a path), and so are
// rows with no path at all. Any twins already present are folded first, or the
// index could not be built.
func onePerFile(db *sql.DB) error {
	if _, err := (&Store{DB: db}).MergeTwins(); err != nil {
		return fmt.Errorf("fold twins before indexing: %w", err)
	}
	_, err := db.Exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS item_one_per_file ON item(path)
		WHERE is_folder = 0 AND path IS NOT NULL AND path <> ''`)
	if err != nil {
		return fmt.Errorf("one item per file: %w", err)
	}
	return nil
}
