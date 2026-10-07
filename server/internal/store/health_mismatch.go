package store

import (
	"path/filepath"
	"strings"
	"unicode"
)

// mismatchedShows finds shows matched to the wrong movie-database entry.
//
// The tell is in the files: a filename that carries an episode title —
// `Dark - 3x01 - Deja-vu` — and a library title that is something else
// entirely, episode after episode. One disagreement is a retitled episode;
// most of a show's named files disagreeing is the show itself being the wrong
// one ("Dark" filed as "Dark Matter"). The fix is Identify, which the card
// opens on the show.
func (s *Store) mismatchedShows() (HealthIssue, error) {
	issue := HealthIssue{Kind: "MismatchedShows", Samples: []HealthSample{}}
	suspects, err := s.showsNamedUnlikeTheirFolders()
	if err != nil || len(suspects) == 0 {
		return issue, err
	}
	in := strings.Repeat("?,", len(suspects))
	args := make([]any, 0, len(suspects))
	for id := range suspects {
		args = append(args, id)
	}
	rows, err := s.DB.Query(`
		SELECT e.series_id, COALESCE(e.series_name, ''), e.name, COALESCE(e.path, '')
		FROM item e
		WHERE e.type = 'Episode' AND e.extra_type IS NULL AND e.path IS NOT NULL
		  AND e.series_id IN (`+in[:len(in)-1]+`)
		ORDER BY e.series_id`, args...)
	if err != nil {
		return issue, err
	}
	defer rows.Close()
	type tally struct {
		name                        string
		named, disagreeing, unnamed int
	}
	shows := map[string]*tally{}
	var order []string
	for rows.Next() {
		var series, seriesName, title, path string
		if rows.Scan(&series, &seriesName, &title, &path) != nil {
			continue
		}
		base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
		fileTitle, ok := TitleFromFilename(base)
		if !ok {
			continue
		}
		t, seen := shows[series]
		if !seen {
			t = &tally{name: seriesName}
			shows[series] = t
			order = append(order, series)
		}
		// Never named at all: the naming pass found nothing under this show
		// to match its files to — "Dark" filed as "Dark Matter".
		if looksUnnamed(title) {
			t.unnamed++
			continue
		}
		t.named++
		if !titlesAgree(fileTitle, title) {
			t.disagreeing++
		}
	}
	for _, id := range order {
		t := shows[id]
		// Five named files at least, and four in five disagreeing: a show
		// with a few retitled episodes is not a wrong match.
		wrongTitles := t.named >= 5 && t.disagreeing*5 >= t.named*4
		neverNamed := t.unnamed >= 5 && t.unnamed*5 >= (t.named+t.unnamed)*4
		if !wrongTitles && !neverNamed {
			continue
		}
		issue.Count++
		if len(issue.Samples) < healthSamples {
			issue.Samples = append(issue.Samples, HealthSample{ID: id, Name: t.name})
		}
	}
	return issue, rows.Err()
}

// titlesAgree: the same title once case, punctuation and spacing are gone,
// or one containing the other — "Pilot" and "Pilot (Part 1)" agree.
func titlesAgree(a, b string) bool {
	norm := func(s string) string {
		var out strings.Builder
		for _, r := range strings.ToLower(s) {
			if unicode.IsLetter(r) || unicode.IsDigit(r) {
				out.WriteRune(r)
			}
		}
		return out.String()
	}
	x, y := norm(a), norm(b)
	if x == "" || y == "" {
		return true
	}
	return x == y || strings.Contains(x, y) || strings.Contains(y, x)
}

// showsNamedUnlikeTheirFolders: shows whose folder, year aside, is neither
// their name nor their original title. The first half of the tell, and cheap —
// it narrows 40,000 episodes to the few shows worth reading. Anime whose files
// are romanised and whose titles are English still have folders that match.
func (s *Store) showsNamedUnlikeTheirFolders() (map[string]bool, error) {
	rows, err := s.DB.Query(`
		SELECT id, name, COALESCE(original_title, ''), COALESCE(path, '') FROM item
		WHERE type = 'Series' AND COALESCE(path, '') <> ''
		  AND NOT EXISTS (SELECT 1 FROM health_dismissed d
		                  WHERE d.kind = 'MismatchedShows' AND d.key = item.id)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id, name, original, path string
		if rows.Scan(&id, &name, &original, &path) != nil {
			continue
		}
		folder := bareTitle(filepath.Base(path))
		if folder != "" && folder != bareTitle(name) && folder != bareTitle(original) {
			out[id] = true
		}
	}
	return out, rows.Err()
}

// bareTitle drops a trailing "(2017)" or "[tvdbid-…]" and everything but
// letters and digits.
func bareTitle(s string) string {
	if i := strings.IndexAny(s, "([{"); i > 0 {
		s = s[:i]
	}
	var out strings.Builder
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			out.WriteRune(r)
		}
	}
	return out.String()
}
