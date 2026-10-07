package scanner

import (
	"database/sql"
	"log/slog"
)

// Every episode in a season.
//
// Lumiere lists a show season by season. An episode with no season belonged
// to no list: a show filed with no season folders (103 of them here) showed
// "No episodes cached yet", and files left loose in a show's own folder
// beside its season folders — OVAs, specials, a stray batch (189 of them) —
// could not be reached from the show at all. Jellyfin seats both, and so
// does this: a show with no seasons gets a Season 1, and loose files beside
// real seasons go to the show's Specials, which the app lists as Extras.
//
// Only rows with no season are touched; nothing already seated moves.
func seatLooseEpisodes(db *sql.DB, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT e.id, e.series_id, COALESCE(s.library_id, ''), COALESCE(s.path, ''),
		       EXISTS (SELECT 1 FROM item x WHERE x.type = 'Season' AND x.parent_id = e.series_id),
		       COALESCE(e.parent_index_number, -1)
		FROM item e JOIN item s ON s.id = e.series_id AND s.type = 'Series'
		WHERE e.type = 'Episode' AND e.season_id IS NULL AND e.series_id IS NOT NULL`)
	if err != nil {
		return 0, err
	}
	type loose struct {
		id, series, library, path string
		hasSeasons                bool
		own                       int
	}
	var all []loose
	for rows.Next() {
		var l loose
		if err := rows.Scan(&l.id, &l.series, &l.library, &l.path, &l.hasSeasons, &l.own); err != nil {
			rows.Close()
			return 0, err
		}
		all = append(all, l)
	}
	rows.Close()
	if err := rows.Err(); err != nil || len(all) == 0 {
		return 0, err
	}

	tx, err := db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	seated := 0
	for _, l := range all {
		// The show had seasons: a loose file is a special. It had none: it is
		// the whole show, and that is season one.
		//
		// But an episode that already knows its season — from its folder or
		// its filename — goes to that season, always. Deciding by whether the
		// show had *any* season put all 146 episodes of New Girl, from seven
		// season folders, into Specials, because a Specials season existed.
		number := 1
		if l.hasSeasons {
			number = 0
		}
		if l.own >= 0 {
			number = l.own
		}
		// Is the season new? If so it is logged as made here, so an undo
		// removes it rather than leaving an empty season behind.
		var existed int
		tx.QueryRow(`SELECT count(*) FROM item WHERE type = 'Season' AND parent_id = ?
			AND index_number = ?`, l.series, number).Scan(&existed)
		season, err := ensureSeason(tx, l.library, l.series, Layout{Season: number, SeriesPath: l.path})
		if err != nil {
			return 0, err
		}
		if existed == 0 {
			if _, err := tx.Exec(`INSERT INTO repair_log (step, item_id, created, at)
				VALUES ('seat', ?, 1, datetime('now'))`, season); err != nil {
				return 0, err
			}
		}
		// The episode as it was, for UndoSeating.
		if _, err := tx.Exec(`
			INSERT INTO repair_log (step, item_id, season_id, parent_id, parent_index_number, at)
			SELECT 'seat', id, season_id, parent_id, parent_index_number, datetime('now')
			FROM item WHERE id = ?`, l.id); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(`
			UPDATE item SET season_id = ?, parent_id = ?,
			    parent_index_number = COALESCE(parent_index_number, ?)
			WHERE id = ?`, season, season, number, l.id); err != nil {
			return 0, err
		}
		seated++
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	log.Info("repair: seated episodes that had no season", "episodes", seated)
	return seated, nil
}

// UndoSeating puts every episode the seating step moved back as it was and
// removes the seasons it made. Returns how many episodes went back.
func UndoSeating(db *sql.DB) (int, error) {
	tx, err := db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	res, err := tx.Exec(`
		UPDATE item SET
		    season_id = (SELECT r.season_id FROM repair_log r WHERE r.step = 'seat' AND r.created = 0 AND r.item_id = item.id),
		    parent_id = (SELECT r.parent_id FROM repair_log r WHERE r.step = 'seat' AND r.created = 0 AND r.item_id = item.id),
		    parent_index_number = (SELECT r.parent_index_number FROM repair_log r WHERE r.step = 'seat' AND r.created = 0 AND r.item_id = item.id)
		WHERE id IN (SELECT item_id FROM repair_log WHERE step = 'seat' AND created = 0)`)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	if _, err := tx.Exec(`DELETE FROM item WHERE id IN (SELECT item_id FROM repair_log WHERE step = 'seat' AND created = 1)
		AND NOT EXISTS (SELECT 1 FROM item e WHERE e.season_id = item.id)`); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(`DELETE FROM repair_log WHERE step IN ('seat', 'reseat')`); err != nil {
		return 0, err
	}
	return int(n), tx.Commit()
}
