package metadata

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"time"
)

// Episode groups: TMDB's other ways of numbering a show.
//
// The naming pass matches an episode by season and episode number against
// TMDB's default listing, and a show split differently on disk matches
// nothing — Justice League's third season is Justice League Unlimited there,
// Gintama's seasons are counted another way. TMDB keeps alternative orders
// for exactly this ("DVD order", "Absolute", "Production"), and the owner can
// choose one per show. Season N on disk is then the group's Nth part, and
// episode E its Eth episode.

const (
	// episodeGroupKind is the item_value on a series naming its chosen group.
	episodeGroupKind = "tmdb:episodegroup"
	// replaceableNameKind marks an episode title that a provider may replace:
	// one taken from the filename, or one written under an order since
	// abandoned. A title someone typed is locked instead, and never carries it.
	replaceableNameKind = "name:replaceable"
)

// EpisodeGroupSummary is one alternative order TMDB offers for a show.
type EpisodeGroupSummary struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Description  string `json:"description"`
	Type         int    `json:"type"`
	GroupCount   int    `json:"group_count"`
	EpisodeCount int    `json:"episode_count"`
}

// EpisodeGroups lists a show's alternative orders.
func (t *TMDB) EpisodeGroups(ctx context.Context, seriesID string) ([]EpisodeGroupSummary, error) {
	var payload struct {
		Results []EpisodeGroupSummary `json:"results"`
	}
	if err := t.get(ctx, "/3/tv/"+seriesID+"/episode_groups", nil, &payload); err != nil {
		return nil, err
	}
	return payload.Results, nil
}

// groupSeason is the facts for one part of a group, keyed as the disk numbers
// them: part `season`, episodes from 1.
func (t *TMDB) groupSeason(ctx context.Context, groupID string, season int) (map[int]EpisodeFacts, error) {
	var payload struct {
		Groups []struct {
			Order    int `json:"order"`
			Episodes []struct {
				Order     int    `json:"order"`
				Name      string `json:"name"`
				Overview  string `json:"overview"`
				StillPath string `json:"still_path"`
				AirDate   string `json:"air_date"`
			} `json:"episodes"`
		} `json:"groups"`
	}
	if err := t.get(ctx, "/3/tv/episode_group/"+groupID, nil, &payload); err != nil {
		return nil, err
	}
	sort.Slice(payload.Groups, func(i, j int) bool { return payload.Groups[i].Order < payload.Groups[j].Order })
	// Parts are ordered from 0 or from 1 depending on who built the group.
	// A group that starts at 0 with a part named for specials still lines up:
	// the disk's season 0 is its specials too.
	for _, part := range payload.Groups {
		if part.Order != season {
			continue
		}
		facts := map[int]EpisodeFacts{}
		for _, ep := range part.Episodes {
			facts[ep.Order+1] = EpisodeFacts{
				StillPath: ep.StillPath, Name: ep.Name, Overview: ep.Overview, AirDate: ep.AirDate,
			}
		}
		return facts, nil
	}
	return nil, fmt.Errorf("group %s has no part %d", groupID, season)
}

// seasonFacts is the listing a batch is named from: the chosen group's part,
// or TMDB's own season.
func (e *Enricher) seasonFacts(ctx context.Context, batch SeasonBatch) (map[int]EpisodeFacts, error) {
	if batch.Group != "" {
		// A season the order does not cover — Justice League's third, which
		// TMDB files as another show — falls back to TMDB's own listing
		// rather than failing on every pass with its synopses cleared.
		if facts, err := e.TMDB.groupSeason(ctx, batch.Group, batch.Season); err == nil {
			return facts, nil
		}
	}
	return e.TMDB.SeasonEpisodes(ctx, batch.TmdbID, batch.Season)
}

// EpisodeGroup is the group chosen for a series, or "".
func (e *Enricher) EpisodeGroup(seriesID string) string {
	var group string
	e.Store.DB.QueryRow(`SELECT value FROM item_value WHERE item_id = ? AND kind = ?`,
		seriesID, episodeGroupKind).Scan(&group)
	return group
}

// SetEpisodeGroup chooses an order for a series ("" for TMDB's own) and
// releases its episodes to be named again under it: their answered-marks go,
// their unlocked titles become replaceable and their unlocked synopses are
// cleared, since both came from the order being abandoned.
func (e *Enricher) SetEpisodeGroup(seriesID, groupID string) error {
	tx, err := e.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = ?`, seriesID, episodeGroupKind); err != nil {
		return err
	}
	if groupID != "" {
		if _, err := tx.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, ?, ?)`,
			seriesID, episodeGroupKind, groupID); err != nil {
			return err
		}
	}
	const unlocked = `type = 'Episode' AND series_id = ? AND extra_type IS NULL
		AND NOT EXISTS (SELECT 1 FROM item_value l WHERE l.item_id = item.id
		                AND l.kind IN ('lock:name', 'lock:overview', 'lock:*'))`
	for _, q := range []string{
		`DELETE FROM item_value WHERE kind IN ('provider:none', 'episode:enriched')
		   AND item_id IN (SELECT id FROM item WHERE ` + unlocked + `)`,
		`INSERT INTO item_value (item_id, kind, value)
		   SELECT id, '` + replaceableNameKind + `', '' FROM item WHERE ` + unlocked + `
		   ON CONFLICT DO NOTHING`,
		`UPDATE item SET overview = NULL WHERE ` + unlocked,
	} {
		if _, err := tx.Exec(q, seriesID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// airedKind is the item_value on a season holding how many of its episodes
// TMDB says have aired — what Library Health compares the files against to
// find episodes missing after the last one on disk.
const airedKind = "tmdb:aired"

// recordAired notes how many episodes of a season have aired, from a listing
// already fetched for naming, so it costs no request of its own.
func (e *Enricher) recordAired(batch SeasonBatch, facts map[int]EpisodeFacts) {
	today := time.Now().UTC().Format("2006-01-02")
	aired := 0
	for number, f := range facts {
		if f.AirDate != "" && f.AirDate <= today && number > aired {
			aired = number
		}
	}
	var anyEpisode string
	for _, id := range batch.Episodes {
		anyEpisode = id
		break
	}
	if aired == 0 || anyEpisode == "" {
		return
	}
	var season string
	e.Store.DB.QueryRow(`SELECT COALESCE(season_id, parent_id, '') FROM item WHERE id = ?`, anyEpisode).Scan(&season)
	if season == "" {
		return
	}
	e.Store.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = ?`, season, airedKind)
	e.Store.DB.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, ?, ?)`,
		season, airedKind, strconv.Itoa(aired))
}
