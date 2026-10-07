package store

import "path/filepath"

// unplacedExtras: extras no show or film can claim — not inside any show's
// folder, and not beside a film that has its folder to itself. They exist and
// play, and no page will ever list them; a folder moved, or a featurette
// filed one level too high, is usually why.
func (s *Store) unplacedExtras() (HealthIssue, error) {
	issue := HealthIssue{Kind: "UnplacedExtras", Samples: []HealthSample{}}
	owners := map[string]bool{}
	rows, err := s.DB.Query(`SELECT type, path FROM item WHERE type IN ('Series', 'Movie')
		AND extra_type IS NULL AND COALESCE(path, '') <> ''`)
	if err != nil {
		return issue, err
	}
	films := map[string]int{}
	for rows.Next() {
		var kind, path string
		if rows.Scan(&kind, &path) != nil {
			continue
		}
		if kind == "Series" {
			owners[path] = true
		} else {
			films[filepath.Dir(path)]++
		}
	}
	rows.Close()
	for dir, n := range films {
		if n == 1 {
			owners[dir] = true
		}
	}
	extras, err := s.DB.Query(`SELECT id, name, path FROM item WHERE extra_type IS NOT NULL
		AND COALESCE(path, '') <> ''
		AND NOT EXISTS (SELECT 1 FROM health_dismissed d WHERE d.kind = 'UnplacedExtras' AND d.key = item.id)
		ORDER BY path`)
	if err != nil {
		return issue, err
	}
	defer extras.Close()
	for extras.Next() {
		var sample HealthSample
		if extras.Scan(&sample.ID, &sample.Name, &sample.Path) != nil {
			continue
		}
		claimed := false
		for dir := filepath.Dir(sample.Path); dir != "/" && dir != "."; dir = filepath.Dir(dir) {
			if owners[dir] {
				claimed = true
				break
			}
		}
		if claimed {
			continue
		}
		issue.Count++
		if len(issue.Samples) < healthSamples {
			issue.Samples = append(issue.Samples, sample)
		}
	}
	return issue, extras.Err()
}
