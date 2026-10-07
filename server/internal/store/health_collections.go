package store

// duplicateCollections finds collections that repeat another: the same name
// once "Collection" is dropped, or every member already inside a larger one.
// Each sample's parts are the collections it repeats, so the card can offer
// to merge it into one of them.
func (s *Store) duplicateCollections() (HealthIssue, error) {
	issue := HealthIssue{Kind: "DuplicateCollections", Samples: []HealthSample{}}
	rows, err := s.DB.Query(`
		SELECT item.id, item.name, d.id, d.name FROM item
		JOIN item d ON d.type = 'BoxSet' AND d.id <> item.id
		WHERE item.type = 'BoxSet' AND (
			(lower(trim(replace(d.name, 'Collection', ''))) = lower(trim(replace(item.name, 'Collection', '')))
			 AND item.id > d.id)
			OR (EXISTS (SELECT 1 FROM link m WHERE m.parent_id = item.id)
			    AND NOT EXISTS (SELECT 1 FROM link m WHERE m.parent_id = item.id
			        AND m.child_id NOT IN (SELECT child_id FROM link o WHERE o.parent_id = d.id))
			    AND (SELECT count(*) FROM link m WHERE m.parent_id = item.id)
			        < (SELECT count(*) FROM link o WHERE o.parent_id = d.id)))
		  AND NOT EXISTS (SELECT 1 FROM health_dismissed x
		                  WHERE x.kind = 'DuplicateCollections' AND x.key = item.id)
		ORDER BY item.name`)
	if err != nil {
		return issue, err
	}
	defer rows.Close()
	index := map[string]int{}
	for rows.Next() {
		var id, name, other, otherName string
		if err := rows.Scan(&id, &name, &other, &otherName); err != nil {
			return issue, err
		}
		at, ok := index[id]
		if !ok {
			issue.Count++
			if len(issue.Samples) >= healthSamples {
				continue
			}
			issue.Samples = append(issue.Samples, HealthSample{ID: id, Name: name})
			at = len(issue.Samples) - 1
			index[id] = at
		}
		issue.Samples[at].Parts = append(issue.Samples[at].Parts, HealthPart{ID: other, Name: otherName})
	}
	return issue, rows.Err()
}
