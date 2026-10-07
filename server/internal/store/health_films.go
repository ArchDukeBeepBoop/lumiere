package store

import (
	"fmt"
	"path/filepath"
	"strings"
)

// duplicateFilms: the same film twice in one library — a second copy, an
// upgrade that never replaced the original, or parts that should be one item.
// One sample per film; its parts are the copies, each described the way the
// choice is made — resolution, codec, range, size, audio and subtitle tracks —
// so the worse one can be hidden without opening either.
func (s *Store) duplicateFilms() (HealthIssue, error) {
	issue := HealthIssue{Kind: "DuplicateFilms", Samples: []HealthSample{}}
	// Two steps, not one: the single query joined every film to its streams
	// and to every other film, and SQLite planned it at 22 seconds on this
	// library. The grouped query finds the handful of duplicates; the details
	// are read for those alone.
	ids, err := s.duplicateFilmIDs()
	if err != nil || len(ids) == 0 {
		return issue, err
	}
	in := strings.Repeat("?,", len(ids))
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	rows, err := s.DB.Query(`
		SELECT m.id, m.name, COALESCE(m.production_year, 0), COALESCE(m.library_id, ''),
		       COALESCE(m.path, ''), COALESCE(m.size, 0),
		       COALESCE((SELECT v.height FROM stream v WHERE v.item_id = m.id AND v.type = 'Video' ORDER BY v.idx LIMIT 1), 0),
		       COALESCE((SELECT v.codec FROM stream v WHERE v.item_id = m.id AND v.type = 'Video' ORDER BY v.idx LIMIT 1), ''),
		       COALESCE((SELECT v.video_range_type FROM stream v WHERE v.item_id = m.id AND v.type = 'Video' ORDER BY v.idx LIMIT 1), ''),
		       (SELECT count(*) FROM stream a WHERE a.item_id = m.id AND a.type = 'Audio'),
		       (SELECT count(*) FROM stream t WHERE t.item_id = m.id AND t.type = 'Subtitle')
		FROM item m WHERE m.id IN (`+in[:len(in)-1]+`)
		ORDER BY m.name, m.production_year, m.library_id, m.size DESC`, args...)
	if err != nil {
		return issue, err
	}
	defer rows.Close()
	index := map[string]int{}
	for rows.Next() {
		var id, name, library, path, codec, rng string
		var year, height, audio, subs int
		var size int64
		if err := rows.Scan(&id, &name, &year, &library, &path, &size, &height, &codec, &rng, &audio, &subs); err != nil {
			return issue, err
		}
		key := fmt.Sprintf("%s|%d|%s", name, year, library)
		at, ok := index[key]
		if !ok {
			issue.Count++
			if len(issue.Samples) >= healthSamples {
				continue
			}
			label := name
			if year > 0 {
				label = fmt.Sprintf("%s (%d)", name, year)
			}
			issue.Samples = append(issue.Samples, HealthSample{ID: id, Name: label, Path: filepath.Dir(path)})
			at = len(issue.Samples) - 1
			index[key] = at
		}
		issue.Samples[at].Parts = append(issue.Samples[at].Parts,
			HealthPart{ID: id, Name: describeCopy(path, size, height, codec, rng, audio, subs)})
	}
	return issue, rows.Err()
}

// describeCopy is "2160p HEVC HDR10 · 18.2 GB · 3 audio · 12 subtitles — file.mkv".
func describeCopy(path string, size int64, height int, codec, rng string, audio, subs int) string {
	out := ""
	if height > 0 {
		out = fmt.Sprintf("%dp", height)
	}
	if codec != "" {
		out += " " + codecName(codec)
	}
	if rng != "" && rng != "SDR" {
		out += " " + rng
	}
	if size > 0 {
		out += fmt.Sprintf(" · %.1f GB", float64(size)/1e9)
	}
	out += fmt.Sprintf(" · %d audio · %d subtitles — %s", audio, subs, filepath.Base(path))
	return out
}

func codecName(c string) string {
	switch c {
	case "hevc", "h265":
		return "HEVC"
	case "h264", "avc":
		return "H.264"
	case "av1":
		return "AV1"
	}
	return c
}

// duplicateFilmIDs: every film sharing its name, year and library with
// another. One grouped pass over the films.
func (s *Store) duplicateFilmIDs() ([]string, error) {
	rows, err := s.DB.Query(`
		SELECT m.id FROM item m JOIN (
			SELECT name, COALESCE(production_year, 0) AS y, COALESCE(library_id, '') AS l
			FROM item WHERE type = 'Movie' AND extra_type IS NULL
			GROUP BY name, y, l HAVING count(*) > 1
		) d ON d.name = m.name AND d.y = COALESCE(m.production_year, 0) AND d.l = COALESCE(m.library_id, '')
		WHERE m.type = 'Movie' AND m.extra_type IS NULL`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		ids = append(ids, id)
	}
	return ids, rows.Err()
}
