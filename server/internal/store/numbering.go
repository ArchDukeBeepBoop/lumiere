package store

import (
	"database/sql"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// episodePatterns are the two spellings that state a season *and* an episode.
//
// Only these two. A bare number in a filename is not evidence — "Gallery Fake
// 2005" and "Episode 1080p" both contain one — and a wrong number is worse than
// no number: it reorders the season and sends a metadata lookup to the wrong
// episode. `S01E02` and `1x02` are unambiguous, and between them they cover
// every file in this library that carries numbering at all.
var episodePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\bs(\d{1,3})[\s._-]*e(\d{1,4})\b`),
	regexp.MustCompile(`(?i)\b(\d{1,3})x(\d{1,4})\b`),
}

// episodeOnlyPatterns are the spellings that state an episode and *not* a
// season: `Episode 2`, `Ep. 2`, `E02`, and the fansub `Title - 02` ending.
//
// Kept apart from episodePatterns on purpose. Those two are strict because a
// wrong number is worse than none; these are looser, and are only safe where
// the caller already knows the file sits inside a show's folder — a bare
// "Episode 1" at the root of a library is nothing, but under `Hoshi no Uta/`
// it is exactly what it says. Jellyfin reads all of these, which is how the
// same folder layout arrived from it as episodes and from this scanner as two
// films both called by the folder's name.
var episodeOnlyPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\bepisode[\s._-]*(\d{1,4})\b`),
	regexp.MustCompile(`(?i)\bep\.?[\s._-]*(\d{1,4})\b`),
	regexp.MustCompile(`(?i)\be(\d{2,4})\b`),
	// A number set off by a dash at the end of the name, which is how fansub
	// groups write it. The dash is the evidence; a trailing year or a
	// resolution is not preceded by one.
	regexp.MustCompile(`\s-\s*(\d{1,4})\s*$`),
}

// ParseEpisodeOnly reads an episode number from a filename that names no
// season. The season is reported as 1, which is what Jellyfin assigns to a show
// whose files sit directly in its folder.
func ParseEpisodeOnly(path string) (season, episode int, ok bool) {
	if _, _, full := ParseEpisodeNumbering(path); full {
		return 0, 0, false
	}
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	for _, pattern := range episodeOnlyPatterns {
		match := pattern.FindStringSubmatch(name)
		if match == nil {
			continue
		}
		e, err := strconv.Atoi(match[1])
		if err != nil || e <= 0 || e >= 2000 {
			continue
		}
		return 1, e, true
	}
	return 0, 0, false
}

// ParseEpisodeNumbering reads a season and episode number out of a filename.
//
// Pure, so the patterns can be tested against real names without a database —
// which matters, because the failure mode of a loose pattern is silent and
// permanent.
func ParseEpisodeNumbering(path string) (season, episode int, ok bool) {
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	for _, pattern := range episodePatterns {
		match := pattern.FindStringSubmatch(name)
		if match == nil {
			continue
		}
		s, err1 := strconv.Atoi(match[1])
		e, err2 := strconv.Atoi(match[2])
		if err1 != nil || err2 != nil {
			continue
		}
		return s, e, true
	}
	return 0, 0, false
}

// NumberEpisodes fills in numbering Jellyfin has not written yet.
//
// The companion to LinkEpisodes and the same bargain: a freshly scanned show has
// no season or episode number until Jellyfin identifies it, and until then the
// episode list is in filename order, Next Up cannot find the next one, and
// nothing can look the episode up with a provider. 1,791 episodes here were in
// that state.
//
// Only rows missing *both* numbers, and only from a filename that states both,
// so nothing Jellyfin has said is overwritten and nothing is guessed.
func NumberEpisodes(db *sql.DB) (int, error) {
	rows, err := db.Query(`
		SELECT id, path FROM item
		WHERE type = 'Episode' AND path IS NOT NULL
		  AND index_number IS NULL AND parent_index_number IS NULL`)
	if err != nil {
		return 0, err
	}

	type numbering struct {
		id              string
		season, episode int
	}
	var found []numbering
	for rows.Next() {
		var id, path string
		if err := rows.Scan(&id, &path); err != nil {
			rows.Close()
			return 0, err
		}
		if season, episode, ok := ParseEpisodeNumbering(path); ok {
			found = append(found, numbering{id, season, episode})
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	if len(found) == 0 {
		return 0, nil
	}

	tx, err := db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`
		UPDATE item SET parent_index_number = ?, index_number = ?
		WHERE id = ? AND index_number IS NULL AND parent_index_number IS NULL`)
	if err != nil {
		return 0, err
	}
	defer stmt.Close()

	for _, n := range found {
		if _, err := stmt.Exec(n.season, n.episode, n.id); err != nil {
			return 0, err
		}
	}
	return len(found), tx.Commit()
}
