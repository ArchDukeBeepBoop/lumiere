package store

import (
	"encoding/json"
	"fmt"
)

// Overnight drift: the library's vital counts, compared backup to backup.
//
// The trial run guards an install; nothing guarded the ordinary days, when a
// scan against a half-mounted drive or a bad repair pass could quietly take
// rows with it. After each nightly backup the counts that must never fall
// without someone meaning it — watched episodes above all — are compared with
// the night before, and a drop is raised in Library Health.

const (
	metaDriftCounts  = "drift_counts"
	metaDriftWarning = "drift_warning"
)

type driftCounts struct {
	Items, Episodes, Watched int
	// Titles filed in collections. Only ever added to by the overnight
	// fill; a fall is a merge or delete done by hand, or damage.
	CollectionMembers int
}

func (s *Store) vitalCounts() (driftCounts, error) {
	var c driftCounts
	err := s.DB.QueryRow(`
		SELECT (SELECT count(*) FROM item),
		       (SELECT count(*) FROM item WHERE type = 'Episode'),
		       (SELECT count(*) FROM user_data WHERE played = 1),
		       (SELECT count(*) FROM link l JOIN item b ON b.id = l.parent_id AND b.type = 'BoxSet')`).Scan(
		&c.Items, &c.Episodes, &c.Watched, &c.CollectionMembers)
	return c, err
}

// CheckDrift compares today's counts with the last check's, records today's,
// and sets or clears the warning Library Health reports.
func (s *Store) CheckDrift() (string, error) {
	now, err := s.vitalCounts()
	if err != nil {
		return "", err
	}
	previous, _ := s.Meta(metaDriftCounts)
	warning := ""
	if previous != "" {
		var was driftCounts
		if json.Unmarshal([]byte(previous), &was) == nil {
			warning = DriftWarning(was, now)
		}
	}
	encoded, _ := json.Marshal(now)
	if err := s.SetMeta(metaDriftCounts, string(encoded)); err != nil {
		return "", err
	}
	return warning, s.SetMeta(metaDriftWarning, warning)
}

// DriftWarning is the sentence for a drop worth raising, or "". Pure.
func DriftWarning(was, now driftCounts) string {
	switch {
	// Bigger than a person unticking a season by hand: more than twenty
	// episodes and more than a twentieth of everything watched.
	case was.Watched-now.Watched > 20 && (was.Watched-now.Watched)*20 > was.Watched:
		return fmt.Sprintf("watched episodes fell from %d to %d since the last backup", was.Watched, now.Watched)
	// A merge or a removed collection takes a handful; a quarter of them at
	// once is not something done by hand.
	case was.CollectionMembers > 20 && (was.CollectionMembers-now.CollectionMembers)*4 > was.CollectionMembers:
		return fmt.Sprintf("titles in collections fell from %d to %d since the last backup",
			was.CollectionMembers, now.CollectionMembers)
	case was.Episodes > 0 && (was.Episodes-now.Episodes)*50 > was.Episodes:
		return fmt.Sprintf("episodes fell from %d to %d since the last backup — is a drive unplugged?",
			was.Episodes, now.Episodes)
	}
	return ""
}

func (s *Store) driftIssue() HealthIssue {
	issue := HealthIssue{Kind: "LibraryShrank", Samples: []HealthSample{}}
	if warning, _ := s.Meta(metaDriftWarning); warning != "" {
		issue.Count = 1
		issue.Samples = append(issue.Samples, HealthSample{ID: "drift", Name: warning})
	}
	return issue
}
