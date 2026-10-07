package metadata

import (
	"context"
	"fmt"
	"time"
)

// Suggesting an episode order for every show that needs one.
//
// Episode Order… marks the order that fits a show's folders, but only when
// someone opens it for that show — and the shows that need it are exactly
// the ones nobody knows to open: their episodes quietly wear filename titles.
// A few are checked each naming pass, and a clear fit is written down for
// Library Health to offer.

const suggestedGroupKind = "tmdb:suggestedgroup"

// SuggestOrders checks up to `limit` shows with filename-named episodes and
// no order chosen or suggested yet, and records the order that fits their
// folders, where one fits every season. Returns how many were suggested.
func (e *Enricher) SuggestOrders(ctx context.Context, limit int) int {
	rows, err := e.Store.DB.Query(`
		SELECT s.id, v.value FROM item s
		JOIN item_value v ON v.item_id = s.id AND v.kind = 'provider:Tmdb'
		WHERE s.type = 'Series'
		  AND NOT EXISTS (SELECT 1 FROM item_value g WHERE g.item_id = s.id
		                  AND g.kind IN ('`+episodeGroupKind+`', '`+suggestedGroupKind+`', 'suggestion:checked'))
		  AND (SELECT count(*) FROM item ep WHERE ep.series_id = s.id AND ep.type = 'Episode'
		       AND `+filenameNameClause("ep")+`) >= 3
		LIMIT ?`, limit)
	if err != nil {
		return 0
	}
	type show struct{ id, tmdb string }
	var shows []show
	for rows.Next() {
		var s show
		if rows.Scan(&s.id, &s.tmdb) == nil {
			shows = append(shows, s)
		}
	}
	rows.Close()

	suggested := 0
	for _, s := range shows {
		// Checked either way, so a show with no fitting order is not asked
		// about again every pass.
		e.Store.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, 'suggestion:checked', ?)
			ON CONFLICT DO NOTHING`, s.id, time.Now().UTC().Format(time.RFC3339))
		groups, err := e.TMDB.EpisodeGroups(ctx, s.tmdb)
		if err != nil || len(groups) == 0 {
			continue
		}
		local := e.LocalSeasonSizes(s.id)
		for i, g := range groups {
			if i >= 6 {
				break
			}
			sizes, err := e.TMDB.PartSizes(ctx, g.ID)
			if err != nil || Fit(local, sizes) < 1 {
				continue
			}
			e.Store.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, ?, ?)
				ON CONFLICT DO NOTHING`, s.id, suggestedGroupKind, fmt.Sprintf("%s\t%s", g.ID, g.Name))
			suggested++
			break
		}
		time.Sleep(250 * time.Millisecond)
	}
	return suggested
}
