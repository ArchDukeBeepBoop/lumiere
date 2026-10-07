package metadata

import (
	"context"
	"fmt"
)

// PendingSeason is a season with no artwork of its own.
type PendingSeason struct {
	ID     string
	Number int
	// TmdbID of the show it belongs to. A season is only findable through its
	// series — TMDB has no season search — so a show that has never been
	// matched has no seasons to fetch either.
	TmdbID string
	Series string
}

// PendingSeasons lists the seasons that would otherwise borrow the show's poster.
//
// Every season of a show drawing the same image is what this is for: 599 of the
// 3,439 seasons here have no artwork, so a season shelf shows the series poster
// four times over and says nothing about which season is which.
//
// A numbered season only. "Season Unknown" is a scanner's way of saying the
// files did not state one, and there is nothing to look up.
func (e *Enricher) PendingSeasons(limit int) ([]PendingSeason, error) {
	rows, err := e.Store.DB.Query(`
		-- The season's own match first, then its show's. A season identified
		-- by hand — a related title bundled in as a season — names a
		-- different show from its parent, and the number within that show.
		SELECT s.id,
		       COALESCE(own_n.value, s.index_number),
		       COALESCE(own.value, v.value),
		       parent.name
		FROM item s
		JOIN item parent ON parent.id = s.parent_id AND parent.type = 'Series'
		LEFT JOIN item_value v ON v.item_id = parent.id AND v.kind = 'provider:Tmdb'
		LEFT JOIN item_value own ON own.item_id = s.id AND own.kind = 'provider:Tmdb'
		LEFT JOIN item_value own_n ON own_n.item_id = s.id AND own_n.kind = 'provider:TmdbSeason'
		WHERE s.type = 'Season' AND COALESCE(own_n.value, s.index_number) IS NOT NULL
		  AND COALESCE(own.value, v.value) IS NOT NULL
		  AND NOT EXISTS (
			SELECT 1 FROM image g WHERE g.item_id = s.id AND g.kind = 'Primary'
		  )
		  -- Not already asked about. Plenty of shows use one poster for every
		  -- season, so "no separate art" is a normal answer and a permanent
		  -- one: without recording it, every run spends its whole budget
		  -- re-asking the same seasons and the count never moves.
		  AND NOT EXISTS (
			SELECT 1 FROM item_value asked
			WHERE asked.item_id = s.id AND asked.kind = 'provider:none'
		  )
		ORDER BY s.date_created DESC
		LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var pending []PendingSeason
	for rows.Next() {
		var season PendingSeason
		if err := rows.Scan(&season.ID, &season.Number, &season.TmdbID, &season.Series); err != nil {
			return nil, err
		}
		pending = append(pending, season)
	}
	return pending, rows.Err()
}

// SeasonPoster is TMDB's artwork for one season.
func (t *TMDB) SeasonPoster(ctx context.Context, seriesID string, season int) (string, error) {
	var payload struct {
		PosterPath string `json:"poster_path"`
	}
	path := fmt.Sprintf("/3/tv/%s/season/%d", seriesID, season)
	if err := t.get(ctx, path, nil, &payload); err != nil {
		return "", err
	}
	return payload.PosterPath, nil
}

// EnrichSeason fetches one season's poster.
//
// Returns whether a picture was stored. A season TMDB has no separate art for
// is ordinary — plenty of shows use one poster throughout — and falling back to
// the series image is the right answer there, which is what already happens.
func (e *Enricher) EnrichSeason(ctx context.Context, season PendingSeason) (bool, error) {
	path, err := e.TMDB.SeasonPoster(ctx, season.TmdbID, season.Number)
	if err != nil {
		return false, err
	}
	if path == "" {
		// TMDB has no separate poster for this season, which is an answer
		// rather than a failure — the show's own image is the right fallback.
		// Recorded so the next run asks about a different season.
		return false, e.markMissed(season.ID)
	}
	if err := e.fetchImage(season.ID, "Primary", "w780"+path); err != nil {
		return false, err
	}
	return true, nil
}
