package store

import (
	"fmt"
	"time"
)

// Segment is one intro, outro or recap mark from Intro Skipper.
type Segment struct {
	ItemID     string
	Type       string
	StartTicks int64
	EndTicks   int64
}

// Segments returns the marks on an item, optionally narrowed to certain types.
//
// The types come from the client as repeated query parameters, and the caller
// has already turned them into a list — the important part is that the list may
// be empty, which means "all of them" rather than "none".
func (s *Store) Segments(itemID string, types []string) ([]Segment, error) {
	query := `SELECT item_id, type, start_ticks, end_ticks FROM segment
	          WHERE item_id = ?`
	args := []any{itemID}
	if len(types) > 0 {
		query += ` AND type IN (` + placeholders(len(types)) + `)`
		for _, t := range types {
			args = append(args, t)
		}
	}
	query += ` ORDER BY start_ticks`

	rows, err := s.DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Segment
	for rows.Next() {
		var seg Segment
		if err := rows.Scan(&seg.ItemID, &seg.Type, &seg.StartTicks, &seg.EndTicks); err != nil {
			return nil, err
		}
		out = append(out, seg)
	}
	return out, rows.Err()
}

// Resume is Continue Watching: started but not finished, most recent first.
//
// Ordered by last_played rather than by when the row was written, because they
// are different things — a re-import rewrites rows without anyone watching
// anything, and ordering on that would reshuffle the shelf for no reason.
//
// Anything past WatchedPercent (90 unless changed) of its runtime is finished, whatever the played flag says.
// A player that stops at the last frame reports that position and nothing marks
// the row watched, so two episodes here sat at 99.99% and stayed on the shelf
// forever. 90% is Jellyfin's own MaxResumePct, which is what the client was
// built against — and it also covers the credits, which is the other place a
// file gets abandoned a few seconds from the end.
const resumeQuery = `
SELECT %s FROM item i
JOIN user_data u ON u.item_id = i.id
WHERE u.position_ticks > 0
  AND u.played = 0
  AND i.extra_type IS NULL
  AND i.is_folder = 0
  -- An unknown runtime cannot be a percentage of anything, so those stay: a
  -- row nobody can measure is better left on the shelf than silently dropped.
  AND (i.runtime_ticks IS NULL OR i.runtime_ticks <= 0
       OR u.position_ticks * 100 < i.runtime_ticks * %d)
  %s
ORDER BY COALESCE(u.last_played, u.updated_at) DESC, i.id
LIMIT ?`

func (s *Store) Resume(videoOnly bool, limit int) ([]Item, error) {
	if limit <= 0 {
		limit = 20
	}
	filter := ""
	if videoOnly {
		// MediaTypes=Video is what the client asks for: a half-played album
		// track does not belong on the Continue Watching shelf.
		filter = "AND i.type IN ('Episode','Movie','Video','Trailer')"
	}
	settings := s.Settings()
	if settings.ResumeWeeks > 0 {
		// Left alone this long, it was abandoned rather than paused.
		since := time.Now().UTC().AddDate(0, 0, -7*settings.ResumeWeeks).Format(time.RFC3339)
		filter += " AND COALESCE(u.last_played, u.updated_at) >= '" + since + "'"
	}
	return s.queryItems(fmt.Sprintf(resumeQuery, itemColumns, settings.WatchedPercent, filter), limit)
}

// Latest is the recently-added shelf, collapsed one row per series.
//
// Collapsing here rather than leaving it to the client is a deliberate answer
// to plan §9.4. Lumiere collapses too, and the two behaviours compose in only
// one direction: collapsing an already-collapsed list changes nothing, while
// collapsing a raw list of episodes turns a limit of 20 rows into however many
// distinct series those 20 episodes happened to belong to — usually three or
// four, and the shelf comes out short. Matching Jellyfin is also simply what
// the client was built against.
const latestQuery = `
SELECT %s FROM item i
WHERE i.id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY COALESCE(series_id, id)
                   ORDER BY date_created DESC, id
               ) AS rank
        FROM item
        WHERE type IN ('Episode','Movie','Series','Video','MusicAlbum')
          AND extra_type IS NULL
          %s
    ) WHERE rank = 1
)
ORDER BY i.date_created DESC, i.id
LIMIT ?`

func (s *Store) Latest(libraryIDs []string, limit int) ([]Item, error) {
	if limit <= 0 {
		limit = 20
	}
	filter := ""
	var args []any
	if len(libraryIDs) > 0 {
		filter = "AND library_id IN (" + placeholders(len(libraryIDs)) + ")"
		for _, id := range libraryIDs {
			args = append(args, id)
		}
	}
	args = append(args, limit)
	return s.queryItems(fmt.Sprintf(latestQuery, itemColumns, filter), args...)
}
