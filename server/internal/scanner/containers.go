package scanner

import (
	"database/sql"
	"fmt"
)

// ensureSeries finds or creates the show a scanned episode belongs to.
//
// By the show's folder first, then by name. The path is the reliable half: it is
// the same string on both sides or it is a different show. Name matching alone
// split twenty-five shows in two on the first run — the folder says `Dr Stone`
// and the scraped title says `Dr. STONE`, so the scanner made a second series
// beside the real one, with no artwork, and filed the new episodes into it.
//
// Name is still tried, because a library reorganised after Jellyfin indexed it
// has the right show under a moved folder, and joining by name is better than a
// duplicate.
func ensureSeries(tx *sql.Tx, libraryID string, layout Layout) (string, error) {
	var id string
	if layout.SeriesPath != "" {
		err := tx.QueryRow(
			`SELECT id FROM item WHERE type = 'Series' AND path = ?`, layout.SeriesPath,
		).Scan(&id)
		if err == nil {
			return id, nil
		}
		if err != sql.ErrNoRows {
			return "", err
		}
	}

	err := tx.QueryRow(
		`SELECT id FROM item WHERE library_id = ? AND type = 'Series' AND name = ?`,
		libraryID, layout.Series,
	).Scan(&id)
	if err == nil {
		return id, nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}

	id = ItemID("series:" + libraryID + ":" + layout.Series)
	var year any
	if layout.Year > 0 {
		year = layout.Year
	}
	// The folder is stored, so the next scan finds this by path rather than
	// making the same guess about the name again.
	// Dated from the folder, not from the scan. A container stamped `now` is a
	// decade-old show reported as added today: seven of them — Absentia, London
	// Has Fallen, The Garden of Sinners — sat at the top of Recently Added for
	// no reason but the moment their row happened to be written.
	_, err = tx.Exec(`
		INSERT INTO item (id, type, name, sort_name, library_id, path, production_year, is_folder, date_created)
		VALUES (?, 'Series', ?, ?, ?, ?, ?, 1, ?)
		ON CONFLICT(id) DO NOTHING`,
		id, layout.Series, layout.Series, libraryID, nullString(layout.SeriesPath), year,
		folderDate(layout.SeriesPath))
	return id, err
}

// ensureSeason does the same for the season beneath it.
func ensureSeason(tx *sql.Tx, libraryID, seriesID string, layout Layout) (string, error) {
	name := "Season Unknown"
	switch {
	case layout.Season == 0:
		name = "Specials"
	case layout.Season > 0:
		name = fmt.Sprintf("Season %d", layout.Season)
	}

	var id string
	err := tx.QueryRow(
		`SELECT id FROM item WHERE type = 'Season' AND parent_id = ? AND name = ?`,
		seriesID, name,
	).Scan(&id)
	if err == nil {
		return id, nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}

	id = ItemID("season:" + seriesID + ":" + name)
	var index any
	if layout.Season >= 0 {
		index = layout.Season
	}
	_, err = tx.Exec(`
		INSERT INTO item (
			id, type, name, sort_name, library_id, parent_id, series_id,
			index_number, is_folder, date_created
		) VALUES (?, 'Season', ?, ?, ?, ?, ?, ?, 1, ?)
		ON CONFLICT(id) DO NOTHING`,
		id, name, name, libraryID, seriesID, seriesID, index,
		folderDate(layout.SeriesPath))
	return id, err
}
