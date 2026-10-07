package metadata

import (
	"context"
	"fmt"
	"time"
)

// SeasonBatch is one season's worth of episodes that have no picture.
//
// Grouped by season, and that is the whole reason this is not per episode:
// TMDB returns a season's episodes in one response, so a season of twenty-four
// costs one request rather than twenty-four. Asking per episode would make a
// library of 39,000 episodes a day's work and a rate limit.
type SeasonBatch struct {
	SeriesName string
	TmdbID     string
	Season     int
	// Group is the TMDB episode group the owner chose for this show, or ""
	// for TMDB's own season order. See episodegroups.go.
	Group string
	// Episodes is episode number → item id, for the ones with no artwork.
	Episodes map[int]string
}

// PendingEpisodeArt lists seasons holding episodes with no picture.
//
// Freshly scanned shows arrive with no episode artwork at all — Jellyfin writes
// stills when it identifies the episodes, which for a show it never identified
// is never. A blank strip of episodes is the most visible gap a new show has.
func (e *Enricher) PendingEpisodeArt(limit int) ([]SeasonBatch, error) {
	rows, err := e.Store.DB.Query(`
		-- The season's own match wins over the show's, for a season identified
		-- by hand as a different show. See PendingSeasons.
		SELECT parent.name,
		       COALESCE(own.value, v.value),
		       COALESCE(own_n.value, ep.parent_index_number),
		       ep.index_number, ep.id, COALESCE(g.value, '')
		FROM item ep
		JOIN item parent ON parent.id = ep.series_id AND parent.type = 'Series'
		LEFT JOIN item_value v ON v.item_id = parent.id AND v.kind = 'provider:Tmdb'
		LEFT JOIN item_value g ON g.item_id = parent.id AND g.kind = '`+episodeGroupKind+`'
		LEFT JOIN item_value own ON own.item_id = ep.parent_id AND own.kind = 'provider:Tmdb'
		LEFT JOIN item_value own_n ON own_n.item_id = ep.parent_id AND own_n.kind = 'provider:TmdbSeason'
		WHERE ep.type = 'Episode' AND ep.extra_type IS NULL
		  AND COALESCE(own.value, v.value) IS NOT NULL
		  -- Not a loose file the repair filed under Specials: its number came
		  -- from a filename, not from the show's list of specials, and TMDB's
		  -- special of that number is almost always another thing entirely.
		  AND NOT EXISTS (SELECT 1 FROM repair_log r WHERE r.step = 'seat' AND r.item_id = ep.id
		                  AND r.created = 0 AND ep.parent_index_number = 0)
		  AND COALESCE(own_n.value, ep.parent_index_number) IS NOT NULL
		  AND ep.index_number IS NOT NULL
		  -- Missing a still, a title, or a synopsis.
		  AND (
			NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = ep.id AND g.kind = 'Primary')
			OR COALESCE(ep.overview, '') = ''
			OR `+filenameNameClause("ep")+`
			OR EXISTS (SELECT 1 FROM item_value r WHERE r.item_id = ep.id AND r.kind = '`+replaceableNameKind+`')
		  )
		  -- Asked and answered: an episode TMDB had nothing for is recorded
		  -- once rather than re-asked every pass.
		  AND NOT EXISTS (
			SELECT 1 FROM item_value asked
			WHERE asked.item_id = ep.id AND asked.kind IN ('provider:none', 'episode:enriched')
		  )
		ORDER BY ep.date_created DESC
		LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Keyed on the pair, because two shows can share a season number and a
	// batch is only meaningful within one series.
	batches := map[string]*SeasonBatch{}
	var order []string
	for rows.Next() {
		var name, tmdbID, group string
		var season, episode int
		var id string
		if err := rows.Scan(&name, &tmdbID, &season, &episode, &id, &group); err != nil {
			return nil, err
		}
		key := tmdbID + "/" + group + "/" + fmt.Sprint(season)
		batch, seen := batches[key]
		if !seen {
			batch = &SeasonBatch{
				SeriesName: name, TmdbID: tmdbID, Season: season, Group: group,
				Episodes: map[int]string{},
			}
			batches[key] = batch
			order = append(order, key)
		}
		batch.Episodes[episode] = id
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := make([]SeasonBatch, 0, len(order))
	for _, key := range order {
		out = append(out, *batches[key])
	}
	return out, nil
}

// EpisodeFacts is what one season listing says about one episode.
type EpisodeFacts struct {
	StillPath string
	Name      string
	Overview  string
	AirDate   string
}

// SeasonEpisodes is every episode TMDB lists for one season: its still, its
// title, its synopsis and its air date, from the one request.
func (t *TMDB) SeasonEpisodes(ctx context.Context, seriesID string, season int) (map[int]EpisodeFacts, error) {
	var payload struct {
		Episodes []struct {
			EpisodeNumber int    `json:"episode_number"`
			StillPath     string `json:"still_path"`
			Name          string `json:"name"`
			Overview      string `json:"overview"`
			AirDate       string `json:"air_date"`
		} `json:"episodes"`
	}
	path := fmt.Sprintf("/3/tv/%s/season/%d", seriesID, season)
	if err := t.get(ctx, path, nil, &payload); err != nil {
		return nil, err
	}

	facts := map[int]EpisodeFacts{}
	for _, episode := range payload.Episodes {
		facts[episode.EpisodeNumber] = EpisodeFacts{
			StillPath: episode.StillPath, Name: episode.Name,
			Overview: episode.Overview, AirDate: episode.AirDate,
		}
	}
	return facts, nil
}

// EnrichEpisodes fetches one season's stills and files them.
//
// Returns how many pictures were stored. Every episode in the batch is marked
// either way — with a picture, or as asked — so a season TMDB has nothing for
// is never queued again.
func (e *Enricher) EnrichEpisodes(ctx context.Context, batch SeasonBatch) (int, error) {
	facts, err := e.seasonFacts(ctx, batch)
	if err != nil {
		return 0, err
	}
	e.recordAired(batch, facts)

	stored := 0
	for number, itemID := range batch.Episodes {
		f, found := facts[number]
		if !found {
			if err := e.markMissed(itemID); err != nil {
				return stored, err
			}
			continue
		}
		if err := e.nameEpisode(itemID, f); err != nil {
			return stored, err
		}
		// Answered, whatever the answer held. Marked before the picture and
		// regardless of it: an episode TMDB names but has no still for is
		// still an episode TMDB has told us everything about, and marking
		// only the ones with pictures is what left fifteen hundred episodes
		// wearing their filenames — the old mark meant "no still", the
		// query read it as "nothing to be had".
		if _, err := e.Store.DB.Exec(`
			INSERT INTO item_value (item_id, kind, value) VALUES (?, 'episode:enriched', ?)
			ON CONFLICT DO NOTHING`, itemID, time.Now().UTC().Format(time.RFC3339)); err != nil {
			return stored, err
		}
		// A null still path joined onto the image base produces a URL that
		// 404s, so it is skipped rather than fetched and failed per episode.
		if f.StillPath == "" {
			continue
		}
		if err := e.fetchImage(itemID, "Primary", "w780"+f.StillPath); err != nil {
			e.Log.Info("metadata: episode still not fetched",
				"series", batch.SeriesName, "episode", number, "reason", err)
			continue
		}
		stored++
	}
	return stored, nil
}

// nameEpisode writes the title, synopsis and air date where the row has none
// of its own. A title the scanner made from the filename counts as none; a
// title someone typed — locked, see store.Edit — is never touched.
func (e *Enricher) nameEpisode(itemID string, f EpisodeFacts) error {
	if f.Name != "" {
		if _, err := e.Store.DB.Exec(`
			UPDATE item SET name = ?, sort_name = ? WHERE id = ?
			  AND (`+filenameNameClause("item")+`
			       OR EXISTS (SELECT 1 FROM item_value r WHERE r.item_id = item.id AND r.kind = '`+replaceableNameKind+`'))
			  AND NOT EXISTS (SELECT 1 FROM item_value l WHERE l.item_id = item.id AND l.kind IN ('lock:name', 'lock:*'))`,
			f.Name, f.Name, itemID); err != nil {
			return err
		}
		if _, err := e.Store.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = '`+replaceableNameKind+`'`, itemID); err != nil {
			return err
		}
	}
	if f.Overview != "" {
		if _, err := e.Store.DB.Exec(`
			UPDATE item SET overview = ? WHERE id = ? AND COALESCE(overview, '') = ''
			  AND NOT EXISTS (SELECT 1 FROM item_value l WHERE l.item_id = item.id AND l.kind IN ('lock:overview', 'lock:*'))`,
			f.Overview, itemID); err != nil {
			return err
		}
	}
	if f.AirDate != "" {
		if _, err := e.Store.DB.Exec(`
			UPDATE item SET premiere_date = ? WHERE id = ? AND premiere_date IS NULL`,
			f.AirDate, itemID); err != nil {
			return err
		}
	}
	return nil
}

// filenameNameClause is true where a row is still called what its file is
// called.
//
// Two shapes of the same thing. The pattern catches what the scanner builds
// for a numbered episode — Show - 1x01 - Title — and the path test catches
// everything else by asking the only question that really matters: is this
// name the file's own name? `Sudden Orange! Episode 1` is neither numbered
// nor obviously a filename, and a title from a provider is better than it.
func filenameNameClause(table string) string {
	return "(" + table + ".name GLOB '* - [0-9]*x[0-9]* - *'" +
		" OR " + table + ".name GLOB '*[Ss][0-9][0-9]*[Ee][0-9][0-9]*'" +
		" OR " + table + ".path LIKE '%/' || " + table + ".name || '.%')"
}
