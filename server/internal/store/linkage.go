package store

import (
	"database/sql"
	"fmt"
)

// LinkEpisodes fills in series and season links Jellyfin has not written yet.
//
// A freshly scanned show arrives with SeriesId and SeasonId set to the all-zero
// GUID — Jellyfin populates them when it identifies the episodes, which can be
// long after the files appear, and until then the episode rows know nothing
// about the show they belong to. Everything keyed on series_id then misreads
// them: Latest partitions by series to show one row per show, so 68 unlinked
// episodes of one anime became 68 separate rows on the shelf.
//
// The parentage is intact the whole time, so the answer is derivable: an
// episode's parent is its season, and a season's parent is its series. Deriving
// it is also more truthful than waiting — the file really is an episode of that
// show; only the metadata pass is outstanding.
//
// Idempotent, and each statement only touches rows that are still missing the
// value, so nothing Jellyfin *has* stated is ever overwritten.
func LinkEpisodes(db *sql.DB) error {
	statements := []struct {
		what string
		sql  string
	}{
		{"season from parent", `
			UPDATE item SET season_id = parent_id
			WHERE type = 'Episode' AND season_id IS NULL
			  AND parent_id IN (SELECT id FROM item WHERE type = 'Season')`},
		{"series from season", `
			UPDATE item SET series_id = (
				SELECT s.parent_id FROM item s
				WHERE s.id = item.season_id AND s.type = 'Season'
			)
			WHERE type = 'Episode' AND series_id IS NULL AND season_id IS NOT NULL`},
		// An episode filed straight under its series, which this library is full
		// of: 9,267 of them at the last count.
		{"series from parent", `
			UPDATE item SET series_id = parent_id
			WHERE type = 'Episode' AND series_id IS NULL
			  AND parent_id IN (SELECT id FROM item WHERE type = 'Series')`},
		{"season's own series", `
			UPDATE item SET series_id = parent_id
			WHERE type = 'Season' AND series_id IS NULL
			  AND parent_id IN (SELECT id FROM item WHERE type = 'Series')`},
		// The name follows the id. A row that knows its series but cannot say
		// which one is half-linked, and every list that prints a series name
		// under an episode would show a blank.
		{"series name", `
			UPDATE item SET series_name = (
				SELECT s.name FROM item s WHERE s.id = item.series_id
			)
			WHERE type IN ('Episode', 'Season')
			  AND series_name IS NULL AND series_id IS NOT NULL`},
	}

	for _, statement := range statements {
		if _, err := db.Exec(statement.sql); err != nil {
			return fmt.Errorf("link %s: %w", statement.what, err)
		}
	}
	return nil
}
