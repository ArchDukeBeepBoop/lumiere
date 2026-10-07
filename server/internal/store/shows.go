package store

import (
	"fmt"
	"path/filepath"
	"strings"
)

// NextUp answers "what do I watch next in each series I have started".
//
// Jellyfin's rule, reproduced: for every series with at least one played
// episode, the lowest-numbered unwatched episode that comes after the furthest
// point reached. Series nobody has begun are excluded — that is what a Latest
// shelf is for, and folding them in turns Next Up into a list of things never
// started.
//
// "After the furthest point reached" rather than "the first unwatched" matters
// on any series watched out of order or with a gap: skipping one episode in the
// middle of season 1 should not park Next Up on it forever while the viewer is
// three seasons ahead.
const nextUpQuery = `
WITH watched AS (
    SELECT e.series_id,
           MAX(COALESCE(e.parent_index_number, 0) * 100000
               + COALESCE(e.index_number, 0)) AS furthest,
           MAX(u.last_played) AS last_played
    FROM item e
    JOIN user_data u ON u.item_id = e.id AND u.played = 1
    WHERE e.type = 'Episode' AND e.series_id IS NOT NULL
      AND COALESCE(e.parent_index_number, 1) <> 0
    GROUP BY e.series_id
)
SELECT %s FROM item i
JOIN watched w ON w.series_id = i.series_id
LEFT JOIN user_data u ON u.item_id = i.id
WHERE i.type = 'Episode'
  AND i.extra_type IS NULL
  -- Specials are never "next": an OVA is a choice, and the loose files the
  -- repair files as Specials would otherwise jump ahead of season one.
  AND COALESCE(i.parent_index_number, 1) <> 0
  AND COALESCE(u.played, 0) = 0
  AND (COALESCE(i.parent_index_number, 0) * 100000
       + COALESCE(i.index_number, 0)) > w.furthest
  AND NOT EXISTS (
      SELECT 1 FROM item earlier
      LEFT JOIN user_data eu ON eu.item_id = earlier.id
      WHERE earlier.series_id = i.series_id
        AND earlier.type = 'Episode'
        AND earlier.extra_type IS NULL
        AND COALESCE(eu.played, 0) = 0
        AND (COALESCE(earlier.parent_index_number, 0) * 100000
             + COALESCE(earlier.index_number, 0)) > w.furthest
        AND (COALESCE(earlier.parent_index_number, 0) * 100000
             + COALESCE(earlier.index_number, 0))
            < (COALESCE(i.parent_index_number, 0) * 100000
               + COALESCE(i.index_number, 0))
  )
  %s
ORDER BY w.last_played DESC
LIMIT ?`

func (s *Store) NextUp(seriesID string, limit int) ([]Item, error) {
	if limit <= 0 {
		limit = 20
	}
	// The home screen asks on every rebuild; the answer changes only when
	// watch state or the episode list does. See nextUpCache.
	fingerprint := s.nextUpFingerprint()
	key := fmt.Sprintf("%p|%s|%d|%s", s.DB, seriesID, limit, fingerprint)
	if fingerprint != "" {
		if items, ok := nextUpCache.get(key); ok {
			return items, nil
		}
	}
	items, err := s.nextUpQuery(seriesID, limit)
	if err == nil && fingerprint != "" {
		nextUpCache.put(key, items)
	}
	return items, err
}

func (s *Store) nextUpQuery(seriesID string, limit int) ([]Item, error) {
	filter := ""
	var args []any
	if seriesID != "" {
		filter = "AND i.series_id = ?"
		args = append(args, seriesID)
	}
	args = append(args, limit)

	return s.queryItems(fmt.Sprintf(nextUpQuery, itemColumns, filter), args...)
}

// Similar scores by shared genres.
//
// Cheap and roughly right, which is the correct trade for a shelf the spec
// calls cosmetic. Restricted to the same type and the same library so a film
// never suggests an episode, and the item itself is excluded — which sounds
// obvious and is the first thing such a query returns, since nothing shares
// more genres with an item than itself.
const similarQuery = `
SELECT %s FROM item i
JOIN item_value v ON v.item_id = i.id AND v.kind = 'genre'
WHERE v.value IN (SELECT value FROM item_value
                  WHERE item_id = ? AND kind = 'genre')
  AND i.id <> ?
  AND i.type = (SELECT type FROM item WHERE id = ?)
  AND (i.library_id = (SELECT library_id FROM item WHERE id = ?)
       OR (SELECT library_id FROM item WHERE id = ?) IS NULL)
  AND i.extra_type IS NULL
GROUP BY i.id
ORDER BY COUNT(*) DESC, i.community_rating DESC, i.sort_name COLLATE NOCASE
LIMIT ?`

func (s *Store) Similar(itemID string, limit int) ([]Item, error) {
	if limit <= 0 {
		limit = 12
	}
	return s.queryItems(fmt.Sprintf(similarQuery, itemColumns),
		itemID, itemID, itemID, itemID, itemID, limit)
}

// Extras are the bonus features attached to an item: anything filed under it
// that carries an ExtraType, which is exactly what the list endpoints exclude.
// Extras are found by where they are, not only by what they are filed under.
//
// Only direct children counted, and almost none are: of 1,006 extras here, 760
// name no parent at all, 180 sit under a season and 66 under a folder the scan
// made for the show's directory — ACCA 13's Extras folder among them, so its
// openings, endings and specials never reached its page. An extra inside a
// show's own folder is that show's, at any depth. A film's are the ones in an
// extras folder beside its file, and only where that folder holds one film —
// a directory of fifty films does not share its extras between them.
const extrasQuery = `
SELECT %s FROM item i
WHERE i.extra_type IS NOT NULL AND (
	i.parent_id = ?
	OR (? <> '' AND i.path LIKE ? ESCAPE '\'))
ORDER BY i.extra_type, i.sort_name COLLATE NOCASE, i.id`

func (s *Store) Extras(itemID string) ([]Item, error) {
	prefix := s.extrasFolder(itemID)
	pattern := ""
	if prefix != "" {
		pattern = likeEscape(prefix) + "/%"
	}
	return s.queryItems(fmt.Sprintf(extrasQuery, itemColumns), itemID, prefix, pattern)
}

// extrasFolder is where an item's extras live: a show's own folder, or a
// film's folder when it is that film's alone. "" when there is no telling.
func (s *Store) extrasFolder(itemID string) string {
	var kind, path string
	s.DB.QueryRow(`SELECT type, COALESCE(path, '') FROM item WHERE id = ?`, itemID).Scan(&kind, &path)
	switch {
	case path == "":
		return ""
	case kind == "Series":
		return path
	case kind == "Movie":
		dir := filepath.Dir(path)
		var films int
		s.DB.QueryRow(`SELECT count(*) FROM item WHERE type = 'Movie' AND extra_type IS NULL
			AND path LIKE ? ESCAPE '\' AND path NOT LIKE ? ESCAPE '\'`,
			likeEscape(dir)+"/%", likeEscape(dir)+"/%/%").Scan(&films)
		if films == 1 {
			return dir
		}
	}
	return ""
}

// likeEscape makes a path safe inside a LIKE pattern.
func likeEscape(p string) string {
	return strings.NewReplacer(`\`, `\\`, "%", `\%`, "_", `\_`).Replace(p)
}

// queryItems runs a hand-written query that shares the standard projection and
// hydrates the result the same way a list does — so an episode from Next Up
// carries the same artwork and watch state as the same episode from /Items.
func (s *Store) queryItems(query string, args ...any) ([]Item, error) {
	rows, err := s.DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Item
	for rows.Next() {
		it, err := scanItem(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, s.hydrate(out)
}
