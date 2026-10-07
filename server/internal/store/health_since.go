package store

import "encoding/json"

// A nightly note of each finding's count, so the report can say what changed
// since — "3 new duplicate films since yesterday" — rather than only that
// something is wrong. Taken with the nightly backup.

const metaHealthSnapshot = "health_snapshot"

// SnapshotHealth records tonight's counts.
func (s *Store) SnapshotHealth() {
	issues, err := s.Health()
	if err != nil {
		return
	}
	counts := map[string]int{}
	for _, i := range issues {
		counts[i.Kind] = i.Count
	}
	raw, _ := json.Marshal(counts)
	s.SetMeta(metaHealthSnapshot, string(raw))
}

// AttachSince fills each issue's Since from the last snapshot, and takes the
// first snapshot if there is none yet, so the comparison starts tonight.
func (s *Store) AttachSince(issues []HealthIssue) {
	raw, _ := s.Meta(metaHealthSnapshot)
	if raw == "" {
		counts := map[string]int{}
		for _, i := range issues {
			counts[i.Kind] = i.Count
		}
		data, _ := json.Marshal(counts)
		s.SetMeta(metaHealthSnapshot, string(data))
		return
	}
	var counts map[string]int
	if json.Unmarshal([]byte(raw), &counts) != nil {
		return
	}
	for i := range issues {
		if n, ok := counts[issues[i].Kind]; ok {
			n := n
			issues[i].Since = &n
		}
	}
}
