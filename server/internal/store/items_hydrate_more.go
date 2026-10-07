package store

import (
	"database/sql"
)

// Split from items_hydrate.go for the 300-line rule.

// hydrateCounts fills ChildCount and RecursiveItemCount.
//
// Both are on the client's decoded list (§5.2, "counts on cards") and neither
// was emitted until the parity harness noticed. ChildCount is the direct
// children — seasons under a series, episodes under a season — and
// RecursiveItemCount is every playable thing beneath, at any depth, which for
// a series is its episodes rather than its seasons.
func (s *Store) hydrateCounts(byID map[string]*Item, in string, args []any) error {
	direct, err := s.countBy(`
		SELECT parent_id, COUNT(*) FROM item
		WHERE parent_id IN (`+in+`) AND extra_type IS NULL
		GROUP BY parent_id`, args)
	if err != nil {
		return err
	}
	// Recursive counts only make sense for the containers that have depth, and
	// series_id is the cheap way to reach every episode of a show without
	// walking seasons.
	recursive, err := s.countBy(`
		SELECT series_id, COUNT(*) FROM item
		WHERE series_id IN (`+in+`) AND type = 'Episode' AND extra_type IS NULL
		GROUP BY series_id`, args)
	if err != nil {
		return err
	}
	// Seasons are counted by season_id, not by parent_id. Only 1,920 of the
	// 3,376 seasons here have any direct child: 9,655 episodes are parented
	// somewhere else entirely — a folder, or the series — while still naming
	// their season. Counting by parent_id leaves nearly half the seasons
	// claiming to be empty.
	inSeason, err := s.countBy(`
		SELECT season_id, COUNT(*) FROM item
		WHERE season_id IN (`+in+`) AND type = 'Episode' AND extra_type IS NULL
		GROUP BY season_id`, args)
	if err != nil {
		return err
	}
	// A series' direct children are not all seasons. 9,267 episodes here are
	// parented straight to the series rather than to a season — the same
	// misparenting that made half the seasons look empty above — so counting
	// parent_id told the card "Hikaru no Go, 80 seasons" when it has 4.
	// Jellyfin's ChildCount for a series is its seasons, so count those.
	seasonsOf, err := s.countBy(`
		SELECT parent_id, COUNT(*) FROM item
		WHERE parent_id IN (`+in+`) AND type = 'Season' AND extra_type IS NULL
		GROUP BY parent_id`, args)
	if err != nil {
		return err
	}
	// Only the seasons that hold something. A scan leaves an empty "Season
	// Unknown" beside the real one on almost every show it has not finished
	// identifying — 320 of them here — so "Gallery Fake, 2 seasons" was counting
	// one season of 37 episodes and one placeholder holding nothing. The season
	// picker already drops those; the count has to agree with it or the card and
	// the page it opens disagree.
	fullSeasonsOf, err := s.countBy(`
		SELECT parent_id, COUNT(*) FROM item s
		WHERE s.parent_id IN (`+in+`) AND s.type = 'Season' AND s.extra_type IS NULL
		  AND EXISTS (
			SELECT 1 FROM item e
			WHERE e.season_id = s.id AND e.type = 'Episode' AND e.extra_type IS NULL
		  )
		GROUP BY parent_id`, args)
	if err != nil {
		return err
	}
	// A library view's children hang off its *physical* folders, not off the
	// view — the same indirection /Items?ParentId= has to resolve — so its
	// count comes from a join through library_folder rather than parent_id.
	views, err := s.countBy(`
		SELECT lf.view_id, COUNT(*) FROM library_folder lf
		JOIN item i ON i.parent_id = lf.folder_id AND i.extra_type IS NULL
		WHERE lf.view_id IN (`+in+`)
		GROUP BY lf.view_id`, args)
	if err != nil {
		return err
	}

	// A collection's members are links. Counted there, "2 of 6 watched" can
	// be said of it at all.
	linked, err := s.countBy(`
		SELECT parent_id, COUNT(*) FROM link WHERE parent_id IN (`+in+`) GROUP BY parent_id`, args)
	if err != nil {
		return err
	}

	for id, it := range byID {
		if !hasChildren(it.Type) {
			continue
		}
		children, ok := direct[id]
		if it.Type == "BoxSet" {
			children, ok = linked[id], true
		}
		if n, found := views[id]; found {
			children, ok = n, true
		}
		if it.Type == "Series" {
			// The raw count stands in when *every* season looks empty: that is a
			// sync that has reached the seasons but not the episodes, and
			// reporting zero there would say the show has no seasons at all.
			if n, found := fullSeasonsOf[id]; found && n > 0 {
				children, ok = n, true
			} else {
				children, ok = seasonsOf[id], true
			}
		}
		if it.Type == "Season" {
			if n, found := inSeason[id]; found {
				children, ok = n, true
			}
		}
		if ok {
			count := children
			it.ChildCount = &count
		}
		total, found := recursive[id]
		if !found {
			// A season or a folder: its children are already the leaves.
			total, found = children, ok
		}
		if found {
			count := total
			it.RecursiveItemCount = &count
		}
	}
	return nil
}

func (s *Store) countBy(query string, args []any) (map[string]int, error) {
	rows, err := s.DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var id sql.NullString
		var n int
		if err := rows.Scan(&id, &n); err != nil {
			return nil, err
		}
		if id.Valid {
			out[id.String] = n
		}
	}
	return out, rows.Err()
}

func hasChildren(t string) bool {
	switch t {
	case "Series", "Season", "Folder", "BoxSet", "CollectionFolder":
		return true
	}
	return false
}
