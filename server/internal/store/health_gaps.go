package store

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
)

// missingEpisodes finds holes in a season's numbering: episodes 1, 2 and 4
// on disk means 3 is missing. Only gaps between episodes that exist — what
// comes after the last one needs a provider to know about, and a season
// still airing would read as broken.
//
// Seasons numbered by one file per range (01-02) or by absolute numbers in
// the hundreds are skipped where the gap is implausibly large: a hole of
// more than twenty is a numbering scheme, not a missing download.
func (s *Store) missingEpisodes() (HealthIssue, error) {
	issue := HealthIssue{Kind: "MissingEpisodes", Samples: []HealthSample{}}
	rows, err := s.DB.Query(`
		SELECT COALESCE(ep.season_id, ep.parent_id, ''), COALESCE(ep.series_id, ''),
		       COALESCE(ep.series_name, ''),
		       COALESCE(ep.parent_index_number, -1), ep.index_number, COALESCE(ep.path, ''),
		       COALESCE((SELECT CAST(a.value AS INTEGER) FROM item_value a
		                 WHERE a.item_id = COALESCE(ep.season_id, ep.parent_id)
		                   AND a.kind = 'tmdb:aired'), 0)
		FROM item ep
		WHERE ep.type = 'Episode' AND ep.extra_type IS NULL
		  AND ep.index_number IS NOT NULL AND ep.index_number > 0
		  AND COALESCE(ep.parent_index_number, 1) > 0
		  AND NOT EXISTS (SELECT 1 FROM health_dismissed d
		                  WHERE (d.kind = 'MissingEpisodes' AND d.key = ep.series_id)
		                     OR (d.kind = 'MissingEpisodesSeason'
		                         AND d.key = COALESCE(ep.season_id, ep.parent_id)))
		ORDER BY 1, ep.index_number`)
	if err != nil {
		return issue, err
	}
	defer rows.Close()

	type season struct {
		series, seriesID, folder string
		number                   int
		have                     []int
		aired                    int
	}
	seasons := map[string]*season{}
	var order []string
	for rows.Next() {
		var id, seriesID, series, path string
		var number, episode, aired int
		if err := rows.Scan(&id, &seriesID, &series, &number, &episode, &path, &aired); err != nil {
			return issue, err
		}
		sn, ok := seasons[id]
		if !ok {
			sn = &season{series: series, seriesID: seriesID, number: number,
				folder: filepath.Dir(path), aired: aired}
			seasons[id] = sn
			order = append(order, id)
		}
		sn.have = append(sn.have, episode)
	}
	if err := rows.Err(); err != nil {
		return issue, err
	}

	// Grouped by show: 132 lines of seasons were a list to scroll, and the
	// decision someone makes — fetch these, or ignore this show — is per show.
	type show struct {
		id, name, folder string
		count            int
		parts            []string
		seasons          []HealthPart
	}
	shows := map[string]*show{}
	var showOrder []string
	for _, id := range order {
		sn := seasons[id]
		holes := EpisodeGaps(sn.have)
		trailing := TrailingGaps(sn.have, sn.aired)
		gaps := append(append([]int{}, holes...), trailing...)
		if len(gaps) == 0 {
			continue
		}
		issue.Count += len(gaps)
		sh, ok := shows[sn.seriesID]
		if !ok {
			sh = &show{id: sn.seriesID, name: sn.series, folder: filepath.Dir(sn.folder)}
			shows[sn.seriesID] = sh
			showOrder = append(showOrder, sn.seriesID)
		}
		sh.count += len(gaps)
		part := GapLabel(sn.number, holes, trailing)
		sh.parts = append(sh.parts, part)
		sh.seasons = append(sh.seasons, HealthPart{ID: id, Name: part})
	}
	sort.SliceStable(showOrder, func(a, b int) bool { return shows[showOrder[a]].count > shows[showOrder[b]].count })
	for _, id := range showOrder {
		if len(issue.Samples) >= healthSamples {
			break
		}
		sh := shows[id]
		issue.Samples = append(issue.Samples, HealthSample{
			ID:    sh.id,
			Name:  fmt.Sprintf("%s — %d missing: %s", sh.name, sh.count, strings.Join(sh.parts, "; ")),
			Path:  sh.folder,
			Parts: sh.seasons,
		})
	}
	return issue, nil
}

// EpisodeGaps lists the numbers missing between the lowest and highest in
// `have`, ignoring any single hole wider than twenty. Pure.
func EpisodeGaps(have []int) []int {
	sort.Ints(have)
	var gaps []int
	for i := 1; i < len(have); i++ {
		hole := have[i] - have[i-1] - 1
		if hole <= 0 || hole > 20 {
			continue
		}
		for n := have[i-1] + 1; n < have[i]; n++ {
			gaps = append(gaps, n)
		}
	}
	// Every other number missing, again and again, is double-episode files
	// (01-02, 03-04) numbered by their first half, not half a season lost.
	if len(gaps) >= 3 && len(gaps)*2 >= len(have)-1 {
		alternating := true
		for i := 1; i < len(have); i++ {
			if have[i]-have[i-1] != 2 {
				alternating = false
				break
			}
		}
		if alternating {
			return nil
		}
	}
	return gaps
}

// TrailingGaps lists the episodes TMDB says have aired after the last one on
// disk. Nothing when TMDB has not been asked (aired 0), and nothing for a gap
// over thirty — that is a season split differently, not a run of downloads
// that never finished.
func TrailingGaps(have []int, aired int) []int {
	if aired == 0 || len(have) == 0 {
		return nil
	}
	last := have[0]
	for _, n := range have {
		last = max(last, n)
	}
	if aired <= last || aired-last > 30 {
		return nil
	}
	var gaps []int
	for n := last + 1; n <= aired; n++ {
		gaps = append(gaps, n)
	}
	return gaps
}

// GapLabel says what a season lacks, in ranges, with holes apart from the
// episodes that aired after the last one here — "season 2: 5, 7–9 missing;
// 11–12 aired since". The two want different things: a hole is usually a
// failed download, a tail is simply not fetched yet. Pure.
func GapLabel(season int, holes, trailing []int) string {
	var parts []string
	if len(holes) > 0 {
		parts = append(parts, Ranges(holes)+" missing")
	}
	if len(trailing) > 0 {
		parts = append(parts, Ranges(trailing)+" aired since")
	}
	return fmt.Sprintf("season %d: %s", season, strings.Join(parts, "; "))
}

// Ranges writes sorted numbers compactly: 1, 3–5, 9.
func Ranges(numbers []int) string {
	sort.Ints(numbers)
	var out []string
	for i := 0; i < len(numbers); {
		j := i
		for j+1 < len(numbers) && numbers[j+1] == numbers[j]+1 {
			j++
		}
		switch {
		case j == i:
			out = append(out, fmt.Sprint(numbers[i]))
		case j == i+1:
			out = append(out, fmt.Sprint(numbers[i]), fmt.Sprint(numbers[j]))
		default:
			out = append(out, fmt.Sprintf("%d–%d", numbers[i], numbers[j]))
		}
		i = j + 1
	}
	return strings.Join(out, ", ")
}
