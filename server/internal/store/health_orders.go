package store

import (
	"fmt"
	"strings"
)

// orderSuggestions lists shows the naming pass found a fitting TMDB episode
// order for. See metadata.SuggestOrders. The sample's Path carries the group
// id, so the client can apply it without asking again.
func (s *Store) orderSuggestions() (HealthIssue, error) {
	issue := HealthIssue{Kind: "OrderSuggestions", Samples: []HealthSample{}}
	rows, err := s.DB.Query(`
		SELECT i.id, i.name, v.value FROM item_value v JOIN item i ON i.id = v.item_id
		WHERE v.kind = 'tmdb:suggestedgroup'
		  AND NOT EXISTS (SELECT 1 FROM item_value g WHERE g.item_id = i.id AND g.kind = 'tmdb:episodegroup')
		  AND NOT EXISTS (SELECT 1 FROM health_dismissed d WHERE d.kind = 'OrderSuggestions' AND d.key = i.id)
		ORDER BY i.name`)
	if err != nil {
		return issue, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, name, value string
		if err := rows.Scan(&id, &name, &value); err != nil {
			return issue, err
		}
		groupID, groupName, _ := strings.Cut(value, "\t")
		issue.Count++
		if len(issue.Samples) < healthSamples {
			issue.Samples = append(issue.Samples, HealthSample{
				ID:   id,
				Name: fmt.Sprintf("%s — its folders follow “%s”", name, groupName),
				Path: groupID,
			})
		}
	}
	return issue, rows.Err()
}
