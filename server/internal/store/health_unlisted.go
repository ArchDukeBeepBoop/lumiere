package store

import "fmt"

// Two checks for things no screen would show.

// unlistedEpisodes are episodes in no season. The repair pass seats every
// one (scanner/seat.go), so this should read zero; a number here means a
// shape the repair did not foresee, found before someone goes looking for an
// episode that is not there.
func (s *Store) unlistedEpisodes() (HealthIssue, error) {
	return s.healthIssue("UnlistedEpisodes", `type = 'Episode' AND extra_type IS NULL AND season_id IS NULL`)
}

// unplacedFiles are videos in a TV library that the scanner could not file
// under any show — usually a folder named in a way no rule recognises.
// Counted per library, with the folders that hold the most.
func (s *Store) unplacedFiles() (HealthIssue, error) {
	issue := HealthIssue{Kind: "UnplacedFiles", Samples: []HealthSample{}}
	// Two plain queries, not one join: joined, the embedded SQLite chose a
	// plan that took three minutes on this library, and the health report
	// runs after every sync.
	libs, err := s.DB.Query(`
		SELECT lf.folder_id, v.name FROM library_folder lf
		JOIN item v ON v.id = lf.view_id WHERE v.collection_type = 'tvshows'`)
	if err != nil {
		return issue, err
	}
	names := map[string]string{}
	for libs.Next() {
		var id, name string
		if libs.Scan(&id, &name) == nil {
			names[id] = name
		}
	}
	libs.Close()
	for id, library := range names {
		rows, err := s.DB.Query(`
			SELECT id, path FROM item
			WHERE library_id = ? AND type = 'Video' AND is_folder = 0 AND extra_type IS NULL
			ORDER BY path`, id)
		if err != nil {
			return issue, err
		}
		for rows.Next() {
			var itemID, path string
			if err := rows.Scan(&itemID, &path); err != nil {
				rows.Close()
				return issue, err
			}
			issue.Count++
			if len(issue.Samples) < healthSamples {
				issue.Samples = append(issue.Samples, HealthSample{
					ID: itemID, Name: fmt.Sprintf("%s — not under any show", library), Path: path,
				})
			}
		}
		rows.Close()
	}
	return issue, nil
}
