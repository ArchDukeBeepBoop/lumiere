package store

import (
	"log/slog"
)

// Shows split across folders, folded back together.
//
// A season or a show's specials copied in under a folder of their own —
// "Because I Don't Like My Big Brother At-All-!!/Specials" beside the show's
// own "Onii-chan no Koto Nanka…" folder — became a second show: on Home as
// new, and paired with the first into a collection of their own. Once the
// metadata pass matches it to the same TMDB show in the same library, its
// seasons and episodes move into the show that was there first.
//
// Only when no episode would collide. Kaze Yuugi and Kaze Yuugi 2 are
// one show to TMDB but two releases here, each with its own episodes 1 to 3;
// folding them would put two episode 1s in one season, so they stay apart.
//
// The folded folder is remembered on the show it joined ("folder:alias"),
// so a later file in it is filed there by the scanner rather than splitting
// the show again. A collection this server made that is left with fewer
// than two members goes; one made by hand is never touched.

// MergeSplitShows folds every such show; returns how many it folded.
func (s *Store) MergeSplitShows(log *slog.Logger) int {
	rows, err := s.DB.Query(`
		SELECT newer.id, older.id, newer.name, COALESCE(newer.path, '')
		FROM item newer
		JOIN item_value nv ON nv.item_id = newer.id AND nv.kind = 'provider:Tmdb' AND nv.value <> ''
		JOIN item_value ov ON ov.kind = 'provider:Tmdb' AND ov.value = nv.value AND ov.item_id <> newer.id
		JOIN item older ON older.id = ov.item_id AND older.type = 'Series' AND older.library_id = newer.library_id
		WHERE newer.type = 'Series'
		  AND (older.date_created < newer.date_created OR (older.date_created = newer.date_created AND
		       (SELECT count(*) FROM item e WHERE e.series_id = older.id) > (SELECT count(*) FROM item e WHERE e.series_id = newer.id)))`)
	if err != nil {
		return 0
	}
	type pair struct{ newer, older, name, path string }
	var pairs []pair
	for rows.Next() {
		var p pair
		rows.Scan(&p.newer, &p.older, &p.name, &p.path)
		pairs = append(pairs, p)
	}
	rows.Close()
	folded := 0
	done := map[string]bool{}
	for _, p := range pairs {
		if done[p.newer] || done[p.older] || s.episodesCollide(p.newer, p.older) {
			continue
		}
		if err := s.foldShow(p.newer, p.older, p.path); err != nil {
			log.Warn("split show: could not fold", "show", p.name, "error", err)
			continue
		}
		done[p.newer] = true
		folded++
		log.Info("split show folded into the one already here", "show", p.name, "folder", p.path)
	}
	if folded > 0 {
		s.dropShrunkenCollections()
	}
	return folded
}

// episodesCollide says whether any episode of a has a season and number b
// already holds.
func (s *Store) episodesCollide(a, b string) bool {
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM item x JOIN item y
		ON y.series_id = ? AND y.type = 'Episode' AND y.extra_type IS NULL
		   AND COALESCE(y.parent_index_number, -1) = COALESCE(x.parent_index_number, -1)
		   AND y.index_number = x.index_number
		WHERE x.series_id = ? AND x.type = 'Episode' AND x.extra_type IS NULL AND x.index_number IS NOT NULL`, b, a).Scan(&n)
	return n > 0
}

// foldShow moves from's seasons and episodes into into, then removes from.
func (s *Store) foldShow(from, into, folder string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var intoName string
	tx.QueryRow(`SELECT name FROM item WHERE id = ?`, into).Scan(&intoName)
	seasons, err := tx.Query(`SELECT id, COALESCE(index_number, -1) FROM item WHERE parent_id = ? AND type = 'Season'`, from)
	if err != nil {
		return err
	}
	type season struct {
		id    string
		index int
	}
	var list []season
	for seasons.Next() {
		var x season
		seasons.Scan(&x.id, &x.index)
		list = append(list, x)
	}
	seasons.Close()
	for _, x := range list {
		var existing string
		tx.QueryRow(`SELECT id FROM item WHERE parent_id = ? AND type = 'Season' AND COALESCE(index_number, -1) = ?`,
			into, x.index).Scan(&existing)
		if existing == "" {
			if _, err := tx.Exec(`UPDATE item SET parent_id = ?, series_id = ?, series_name = ? WHERE id = ?`,
				into, into, intoName, x.id); err != nil {
				return err
			}
			if _, err := tx.Exec(`UPDATE item SET series_id = ?, series_name = ? WHERE parent_id = ?`, into, intoName, x.id); err != nil {
				return err
			}
			continue
		}
		if _, err := tx.Exec(`UPDATE item SET parent_id = ?, season_id = ?, series_id = ?, series_name = ? WHERE parent_id = ?`,
			existing, existing, into, intoName, x.id); err != nil {
			return err
		}
		if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, x.id); err != nil {
			return err
		}
	}
	// Anything filed straight under the show.
	if _, err := tx.Exec(`UPDATE item SET parent_id = ?, series_id = ?, series_name = ? WHERE parent_id = ?`,
		into, into, intoName, from); err != nil {
		return err
	}
	if folder != "" {
		if _, err := tx.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?, 'folder:alias', ?)`, into, folder); err != nil {
			return err
		}
	}
	tx.Exec(`DELETE FROM link WHERE child_id = ?`, from)
	tx.Exec(`DELETE FROM item_value WHERE item_id = ?`, from)
	if _, err := tx.Exec(`DELETE FROM item WHERE id = ?`, from); err != nil {
		return err
	}
	return tx.Commit()
}

// dropShrunkenCollections removes collections this server made — a
// franchise or an automatic one — left with fewer than two members. One
// made or identified by hand is left as it is.
func (s *Store) dropShrunkenCollections() {
	s.DB.Exec(`DELETE FROM item WHERE type = 'BoxSet'
		AND EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = item.id
		            AND v.kind IN ('anilist:franchise', 'auto:collection'))
		AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = item.id AND v.kind = 'lock:name')
		AND (SELECT count(*) FROM link l WHERE l.parent_id = item.id) < 2`)
	s.DB.Exec(`DELETE FROM link WHERE parent_id NOT IN (SELECT id FROM item)`)
	s.DB.Exec(`DELETE FROM item_value WHERE kind IN ('anilist:franchise', 'auto:collection')
		AND item_id NOT IN (SELECT id FROM item)`)
}
