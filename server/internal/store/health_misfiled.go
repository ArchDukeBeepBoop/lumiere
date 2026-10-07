package store

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// misfiledEpisodes finds episodes whose file names one season while the
// library files them under another: `Show - S01E12.mkv` sitting in
// Season 2. The usual cause of a gap in one season and a stray in the next —
// and the answer to "where did episode twelve go" is usually "next door".
func (s *Store) misfiledEpisodes() (HealthIssue, error) {
	issue := HealthIssue{Kind: "MisfiledEpisodes", Samples: []HealthSample{}}
	rows, err := s.DB.Query(`
		SELECT id, COALESCE(series_name, ''), path
		FROM item
		WHERE type = 'Episode' AND extra_type IS NULL AND path IS NOT NULL
		  AND NOT EXISTS (SELECT 1 FROM health_dismissed d
		                  WHERE d.kind = 'MisfiledEpisodes' AND d.key = item.id)
		ORDER BY path`)
	if err != nil {
		return issue, err
	}
	defer rows.Close()
	type file struct {
		id, series, path, named string
		season                  int
	}
	folders := map[string][]file{}
	var order []string
	for rows.Next() {
		var f file
		if err := rows.Scan(&f.id, &f.series, &f.path); err != nil {
			return issue, err
		}
		if _, ok := FolderSeason(f.path); !ok {
			continue
		}
		season, named, ok := NamedSeason(f.path)
		if !ok {
			continue
		}
		f.season, f.named = season, named
		dir := filepath.Dir(f.path)
		if _, seen := folders[dir]; !seen {
			order = append(order, dir)
		}
		folders[dir] = append(folders[dir], f)
	}
	if err := rows.Err(); err != nil {
		return issue, err
	}
	for _, dir := range order {
		files := folders[dir]
		seasons := make([]int, len(files))
		for i, f := range files {
			seasons[i] = f.season
		}
		majority, ok := Majority(seasons)
		if !ok {
			continue
		}
		folderSeason, _ := FolderSeason(files[0].path)
		for _, f := range files {
			if f.season == majority {
				continue
			}
			issue.Count++
			if len(issue.Samples) < healthSamples {
				issue.Samples = append(issue.Samples, HealthSample{
					ID:   f.id,
					Name: fmt.Sprintf("%s — %s sits in the season %d folder among season %d files", f.series, f.named, folderSeason, majority),
					Path: f.path,
				})
			}
		}
	}
	return issue, nil
}

var lastSxE = regexp.MustCompile(`(?i)(?:\bS(\d{1,2})E(\d{1,4})|\b(\d{1,2})x(\d{1,4})\b)`)

// NamedSeason is the season the *last* SxE marker in a file name gives —
// the last, because a title can carry a number pattern of its own ("3x3
// Eyes - 1x01") before the real one. Specials (season 0) are left out. Pure.
func NamedSeason(path string) (int, string, bool) {
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	all := lastSxE.FindAllStringSubmatch(name, -1)
	if len(all) == 0 {
		return 0, "", false
	}
	m := all[len(all)-1]
	season, episode := m[1], m[2]
	if season == "" {
		season, episode = m[3], m[4]
	}
	n, _ := strconv.Atoi(season)
	e, _ := strconv.Atoi(episode)
	if n == 0 {
		return 0, "", false
	}
	return n, fmt.Sprintf("S%02dE%02d", n, e), true
}

// Majority is the season most files in a folder carry, if one clearly
// leads (more than half). A folder with no clear majority is left alone:
// there is no telling which files are the strays. Pure.
func Majority(seasons []int) (int, bool) {
	if len(seasons) < 3 {
		return 0, false
	}
	counts := map[int]int{}
	for _, s := range seasons {
		counts[s]++
	}
	for s, c := range counts {
		if c*2 > len(seasons) {
			return s, true
		}
	}
	return 0, false
}

// Misfiled reports the SxE a file's name gives when its season differs from
// the one it is filed under. Pure. Season 0 in a name (a special) is not a
// misfiling — specials are routinely kept beside the season they belong to.
func Misfiled(path string, filedSeason int) (string, bool) {
	season, episode, ok := ParseEpisodeNumbering(filepath.Base(path))
	if !ok || season == 0 || season == filedSeason {
		return "", false
	}
	return fmt.Sprintf("S%02dE%02d", season, episode), true
}

var seasonFolder = regexp.MustCompile(`(?i)^(?:season|series|s)\s*0*(\d{1,3})\b`)

// FolderSeason is the season number a file's folder names — "Season 2",
// "S02", "Season 21 - Egghead Arc" — and whether it names one at all. The
// library numbers an episode from its file name, so the folder is the only
// independent witness to where it was meant to be. Pure.
func FolderSeason(path string) (int, bool) {
	m := seasonFolder.FindStringSubmatch(filepath.Base(filepath.Dir(path)))
	if m == nil {
		return 0, false
	}
	n, err := strconv.Atoi(m[1])
	return n, err == nil
}
