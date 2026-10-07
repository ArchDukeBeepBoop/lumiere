package store

import (
	"database/sql"
	"fmt"
	"strings"
)

// Library health: the kinds of damage every past cleanup was about, counted
// so the owner can see them rather than finding them one tile at a time.

// HealthIssue is one kind of problem: how many, and a few to look at.
type HealthIssue struct {
	Kind    string
	Count   int
	Samples []HealthSample
	// Since is the count at last night's snapshot, when there is one — so a
	// finding can say "3 new since yesterday". See SnapshotHealth.
	Since *int `json:",omitempty"`
}

// HealthSample is one affected item. Parts, where present, are its pieces
// that can be dealt with one at a time — a show's seasons, for missing
// episodes.
type HealthSample struct {
	ID, Name, Path string
	Parts          []HealthPart `json:",omitempty"`
}

// HealthPart is one piece of a sample.
type HealthPart struct {
	ID, Name string
}

// healthSamples is how many examples each kind carries. Enough to recognise
// the pattern; the count says how far it goes.
const healthSamples = 12

// Health counts each kind of damage.
func (s *Store) Health() ([]HealthIssue, error) {
	checks := []struct{ kind, where string }{
		// A show with nothing under it: drawn as a poster that opens on nothing.
		{"EmptySeries", `type = 'Series' AND NOT EXISTS (
			SELECT 1 FROM item e WHERE e.series_id = item.id AND e.type = 'Episode')`},
		// A file with no picture of its own and none taken from it yet.
		{"MissingArtwork", `type IN ('Movie','Episode','Video') AND is_folder = 0
			AND extra_type IS NULL AND NOT EXISTS (
			SELECT 1 FROM image g WHERE g.item_id = item.id AND g.kind = 'Primary')`},
		// A file ffprobe found no duration in: empty, truncated or not video.
		// The all-zero download is one of these.
		{"Unreadable", `type IN ('Movie','Episode','Video') AND is_folder = 0
			AND COALESCE(runtime_ticks, 0) = 0 AND NOT EXISTS (
			SELECT 1 FROM stream st WHERE st.item_id = item.id)`},
		// Collections: empty, twice over, or pointing at titles that are gone.
		{"EmptyCollections", `type = 'BoxSet' AND NOT EXISTS (
			SELECT 1 FROM link l WHERE l.parent_id = item.id)`},
		{"CollectionsWithGoneTitles", `type = 'BoxSet' AND EXISTS (
			SELECT 1 FROM link l WHERE l.parent_id = item.id
			AND NOT EXISTS (SELECT 1 FROM item c WHERE c.id = l.child_id))`},
	}
	var out []HealthIssue
	for _, c := range checks {
		issue, err := s.healthIssue(c.kind, c.where)
		if err != nil {
			return nil, err
		}
		out = append(out, issue)
	}
	unnamed, err := s.unnamedEpisodes()
	if err != nil {
		return nil, err
	}
	out = append(out, unnamed)
	films, err := s.duplicateFilms()
	if err != nil {
		return nil, err
	}
	out = append(out, films)
	stray, err := s.unplacedExtras()
	if err != nil {
		return nil, err
	}
	out = append(out, stray)
	wrong, err := s.mismatchedShows()
	if err != nil {
		return nil, err
	}
	out = append(out, wrong)
	dupes, err := s.duplicateCollections()
	if err != nil {
		return nil, err
	}
	out = append(out, dupes)
	gaps, err := s.missingEpisodes()
	if err != nil {
		return nil, err
	}
	misfiled, err := s.misfiledEpisodes()
	if err != nil {
		return nil, err
	}
	LinkGapsToMisfiled(&gaps, misfiled)
	orders, err := s.orderSuggestions()
	if err != nil {
		return nil, err
	}
	unlisted, err := s.unlistedEpisodes()
	if err != nil {
		return nil, err
	}
	unplaced, err := s.unplacedFiles()
	if err != nil {
		return nil, err
	}
	return append(out, gaps, misfiled, orders, unlisted, unplaced, s.driftIssue(), s.restoreIssue()), nil
}

func (s *Store) healthIssue(kind, where string) (HealthIssue, error) {
	issue := HealthIssue{Kind: kind, Samples: []HealthSample{}}
	if err := s.DB.QueryRow(`SELECT count(*) FROM item WHERE ` + where).Scan(&issue.Count); err != nil {
		return issue, err
	}
	rows, err := s.DB.Query(`
		SELECT id, name, COALESCE(path, '') FROM item WHERE `+where+`
		ORDER BY date_created DESC LIMIT ?`, healthSamples)
	if err != nil {
		return issue, err
	}
	return issue, scanSamples(rows, &issue)
}

// unnamedEpisodes are episodes still wearing their filename — the naming
// pass found no listing for them. Judged in Go by the same rule MergeTwins
// uses, since "looks like a filename" is not something SQL can say.
func (s *Store) unnamedEpisodes() (HealthIssue, error) {
	issue := HealthIssue{Kind: "UnnamedEpisodes", Samples: []HealthSample{}}
	rows, err := s.DB.Query(`
		SELECT id, name, COALESCE(path, '') FROM item
		WHERE type = 'Episode' AND extra_type IS NULL
		ORDER BY date_created DESC`)
	if err != nil {
		return issue, err
	}
	defer rows.Close()
	for rows.Next() {
		var sample HealthSample
		if err := rows.Scan(&sample.ID, &sample.Name, &sample.Path); err != nil {
			return issue, err
		}
		if !looksUnnamed(sample.Name) {
			continue
		}
		issue.Count++
		if len(issue.Samples) < healthSamples {
			issue.Samples = append(issue.Samples, sample)
		}
	}
	return issue, rows.Err()
}

func scanSamples(rows *sql.Rows, issue *HealthIssue) error {
	defer rows.Close()
	for rows.Next() {
		var sample HealthSample
		if err := rows.Scan(&sample.ID, &sample.Name, &sample.Path); err != nil {
			return err
		}
		issue.Samples = append(issue.Samples, sample)
	}
	return rows.Err()
}

// DismissHealth leaves one finding alone from now on: for MissingEpisodes the
// key is the show's id. Undone by RestoreHealth.
func (s *Store) DismissHealth(kind, key string) error {
	_, err := s.DB.Exec(`INSERT INTO health_dismissed (kind, key) VALUES (?, ?) ON CONFLICT DO NOTHING`, kind, key)
	return err
}

// RestoreHealth brings every dismissed finding back.
func (s *Store) RestoreHealth() (int, error) {
	result, err := s.DB.Exec(`DELETE FROM health_dismissed`)
	if err != nil {
		return 0, err
	}
	n, _ := result.RowsAffected()
	return int(n), nil
}

// LinkGapsToMisfiled notes, on a show's missing-episode line, that it also
// has misfiled files — usually the same episodes, filed one season over. A
// gap that is really a stray is a move, not a download. Pure.
func LinkGapsToMisfiled(gaps *HealthIssue, misfiled HealthIssue) {
	strays := map[string]int{}
	for _, m := range misfiled.Samples {
		series, _, _ := strings.Cut(m.Name, " — ")
		strays[series]++
	}
	for i, g := range gaps.Samples {
		series, _, _ := strings.Cut(g.Name, " — ")
		if n := strays[series]; n > 0 {
			gaps.Samples[i].Name = fmt.Sprintf("%s (%d misfiled file%s below may be these)",
				g.Name, n, map[bool]string{true: "", false: "s"}[n == 1])
		}
	}
}
