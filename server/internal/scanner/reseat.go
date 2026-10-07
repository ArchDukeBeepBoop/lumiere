package scanner

import (
	"database/sql"
	"log/slog"
)

// reseatBySeasonNumber undoes the seating step's one mistake: episodes it put
// in a season other than their own. It seated by whether the show had any
// season, not by the season the episode's folder named, so whole shows went
// into Specials — New Girl's seven seasons, Happy Endings' three.
//
// Only episodes in a season the seating step made, whose own season number
// is known and differs, are moved: to the season of that number, made if
// needed. Seasons the step made that are left empty are removed. Each move
// is logged, as the seating was.
func reseatBySeasonNumber(db *sql.DB, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT e.id, e.series_id, COALESCE(s.library_id, ''), COALESCE(s.path, ''), e.parent_index_number
		FROM item e
		JOIN item z ON z.id = e.season_id AND z.type = 'Season'
		JOIN item s ON s.id = e.series_id AND s.type = 'Series'
		WHERE e.type = 'Episode' AND e.parent_index_number IS NOT NULL
		  AND COALESCE(z.index_number, -1) <> e.parent_index_number
		  AND z.id IN (SELECT item_id FROM repair_log WHERE step = 'seat' AND created = 1)`)
	if err != nil {
		return 0, err
	}
	type move struct {
		id, series, library, path string
		number                    int
	}
	var moves []move
	for rows.Next() {
		var m move
		if err := rows.Scan(&m.id, &m.series, &m.library, &m.path, &m.number); err != nil {
			rows.Close()
			return 0, err
		}
		moves = append(moves, m)
	}
	rows.Close()
	if len(moves) == 0 {
		return 0, rows.Err()
	}
	tx, err := db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	for _, m := range moves {
		var existed int
		tx.QueryRow(`SELECT count(*) FROM item WHERE type = 'Season' AND parent_id = ? AND index_number = ?`,
			m.series, m.number).Scan(&existed)
		season, err := ensureSeason(tx, m.library, m.series, Layout{Season: m.number, SeriesPath: m.path})
		if err != nil {
			return 0, err
		}
		if existed == 0 {
			tx.Exec(`INSERT INTO repair_log (step, item_id, created, at) VALUES ('seat', ?, 1, datetime('now'))`, season)
		}
		if _, err := tx.Exec(`
			INSERT INTO repair_log (step, item_id, season_id, parent_id, parent_index_number, at)
			SELECT 'reseat', id, season_id, parent_id, parent_index_number, datetime('now') FROM item WHERE id = ?`, m.id); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(`UPDATE item SET season_id = ?, parent_id = ? WHERE id = ?`, season, season, m.id); err != nil {
			return 0, err
		}
	}
	// The seasons the step made that nothing is in any more.
	if _, err := tx.Exec(`DELETE FROM item WHERE type = 'Season'
		AND id IN (SELECT item_id FROM repair_log WHERE step = 'seat' AND created = 1)
		AND NOT EXISTS (SELECT 1 FROM item e WHERE e.season_id = item.id OR e.parent_id = item.id)`); err != nil {
		return 0, err
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	log.Info("repair: moved seated episodes into their own seasons", "episodes", len(moves))
	return len(moves), nil
}
