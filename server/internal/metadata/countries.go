package metadata

import (
	"context"
	"database/sql"
	"strings"
	"time"
)

// Where a title comes from, for the country filter.
//
// Written with the rest of a match (see apply), and filled in afterwards for
// titles matched before countries were asked for: one details request each,
// marked `countries:checked` so a title with no country on TMDB is not asked
// about again.

// writeCountries replaces an item's countries and marks it checked.
func writeCountries(tx *sql.Tx, itemID string, codes []string) error {
	if _, err := tx.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = 'country'`, itemID); err != nil {
		return err
	}
	for _, code := range codes {
		if _, err := tx.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, 'country', ?)
			ON CONFLICT DO NOTHING`, itemID, code); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, 'countries:checked', ?)
		ON CONFLICT DO NOTHING`, itemID, time.Now().UTC().Format("2006-01-02")); err != nil {
		return err
	}
	// item_value has no change trigger, so say so: the apps re-read changed
	// items from the change feed, and a country nobody is told about never
	// reaches the filter.
	_, err := tx.Exec(`INSERT INTO change_log (item_id) VALUES (?)`, itemID)
	return err
}

// PendingCountries lists matched films and shows whose country was never asked.
func (e *Enricher) PendingCountries(limit int) ([]Pending, error) {
	rows, err := e.Store.DB.Query(`
		SELECT i.id, i.type, i.name, COALESCE(i.production_year, 0), v.value
		FROM item i
		JOIN item_value v ON v.item_id = i.id AND v.kind = 'provider:Tmdb'
		WHERE i.type IN ('Movie', 'Series')
		  AND NOT EXISTS (SELECT 1 FROM item_value c WHERE c.item_id = i.id AND c.kind = 'countries:checked')
		LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Pending
	for rows.Next() {
		var p Pending
		if err := rows.Scan(&p.ID, &p.Type, &p.Name, &p.Year, &p.TmdbID); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Country asks TMDB where one matched title comes from and records it.
func (e *Enricher) Country(ctx context.Context, item Pending) error {
	var details Details
	var err error
	if item.Type == "Series" {
		details, err = e.TMDB.Series(ctx, item.TmdbID)
	} else {
		details, err = e.TMDB.Movie(ctx, item.TmdbID)
	}
	if err != nil {
		return err
	}
	tx, err := e.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := writeCountries(tx, item.ID, details.Countries); err != nil {
		return err
	}
	return tx.Commit()
}

// countriesOf is the origin, else where it was made, as upper-case codes
// without repeats. A co-production is filed under each of its countries.
func countriesOf(origin []string, production []struct {
	Code string `json:"iso_3166_1"`
}) []string {
	codes := origin
	if len(codes) == 0 {
		for _, p := range production {
			codes = append(codes, p.Code)
		}
	}
	seen := map[string]bool{}
	var out []string
	for _, c := range codes {
		c = strings.ToUpper(strings.TrimSpace(c))
		if len(c) == 2 && !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	return out
}
