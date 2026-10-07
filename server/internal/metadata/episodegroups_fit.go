package metadata

import (
	"context"
)

// Which of TMDB's episode orders matches the folders on disk.
//
// Choosing an order is a guess from its name — "DVD", "Absolute" — unless
// something says which one this library's files follow. The number of
// episodes in each season folder does: an order whose parts have the same
// counts is almost certainly the one the release used.

// PartSizes is how many episodes each part of a group has, keyed by the
// part's order (its season number on disk).
func (t *TMDB) PartSizes(ctx context.Context, groupID string) (map[int]int, error) {
	var payload struct {
		Groups []struct {
			Order    int               `json:"order"`
			Episodes []groupEpisodeRef `json:"episodes"`
		} `json:"groups"`
	}
	if err := t.get(ctx, "/3/tv/episode_group/"+groupID, nil, &payload); err != nil {
		return nil, err
	}
	sizes := map[int]int{}
	for _, g := range payload.Groups {
		sizes[g.Order] = len(g.Episodes)
	}
	return sizes, nil
}

type groupEpisodeRef struct {
	Order int `json:"order"`
}

// Fit is the share of the library's seasons (specials aside) whose episode
// count equals the group's part of the same number, 0–1. Pure.
func Fit(local, group map[int]int) float64 {
	seasons, matched := 0, 0
	for season, count := range local {
		if season == 0 {
			continue
		}
		seasons++
		if group[season] == count {
			matched++
		}
	}
	if seasons == 0 {
		return 0
	}
	return float64(matched) / float64(seasons)
}

// LocalSeasonSizes counts the episodes of a series per season number.
func (e *Enricher) LocalSeasonSizes(seriesID string) map[int]int {
	rows, err := e.Store.DB.Query(`
		SELECT COALESCE(parent_index_number, -1), count(*) FROM item
		WHERE series_id = ? AND type = 'Episode' AND extra_type IS NULL
		GROUP BY 1`, seriesID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	sizes := map[int]int{}
	for rows.Next() {
		var season, n int
		if rows.Scan(&season, &n) == nil && season >= 0 {
			sizes[season] = n
		}
	}
	return sizes
}
