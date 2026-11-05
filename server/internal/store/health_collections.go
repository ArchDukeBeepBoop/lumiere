package store

import (
	"sort"
	"strings"
)

// duplicateCollections finds collections that repeat another: the same name
// once "Collection" is dropped, or every member already inside a larger one.
// Each sample's parts are the collections it repeats, so the card can offer
// to merge it into one of them.
func (s *Store) duplicateCollections() (HealthIssue, error) {
	issue := HealthIssue{Kind: "DuplicateCollections", Samples: []HealthSample{}}
	// Compared in memory, not in one SQL join of every collection with every
	// other: that ran nested link lookups for each of sixty thousand pairs,
	// and the report runs after every sync.
	type box struct {
		id, name, key string
		members       map[string]bool
	}
	rows, err := s.DB.Query(`SELECT id, name FROM item i WHERE type = 'BoxSet'
		AND NOT EXISTS (SELECT 1 FROM health_dismissed x WHERE x.kind = 'DuplicateCollections' AND x.key = i.id)`)
	if err != nil {
		return issue, err
	}
	var boxes []*box
	byID := map[string]*box{}
	for rows.Next() {
		b := &box{members: map[string]bool{}}
		if err := rows.Scan(&b.id, &b.name); err != nil {
			rows.Close()
			return issue, err
		}
		b.key = strings.ToLower(strings.TrimSpace(strings.ReplaceAll(b.name, "Collection", "")))
		boxes = append(boxes, b)
		byID[b.id] = b
	}
	rows.Close()
	// Every collection is a candidate "other", dismissed or not.
	others := append([]*box(nil), boxes...)
	if rows, err = s.DB.Query(`SELECT id, name FROM item WHERE type = 'BoxSet'`); err == nil {
		for rows.Next() {
			var id, name string
			rows.Scan(&id, &name)
			if byID[id] == nil {
				b := &box{id: id, name: name, members: map[string]bool{},
					key: strings.ToLower(strings.TrimSpace(strings.ReplaceAll(name, "Collection", "")))}
				byID[id] = b
				others = append(others, b)
			}
		}
		rows.Close()
	}
	links, err := s.DB.Query(`SELECT l.parent_id, l.child_id FROM link l JOIN item b ON b.id = l.parent_id AND b.type = 'BoxSet'`)
	if err != nil {
		return issue, err
	}
	for links.Next() {
		var parent, child string
		links.Scan(&parent, &child)
		if b := byID[parent]; b != nil {
			b.members[child] = true
		}
	}
	links.Close()
	sort.Slice(boxes, func(i, j int) bool { return boxes[i].name < boxes[j].name })
	for _, item := range boxes {
		var parts []HealthPart
		for _, d := range others {
			if d.id == item.id {
				continue
			}
			sameName := d.key == item.key && item.id > d.id
			within := len(item.members) > 0 && len(item.members) < len(d.members)
			if within {
				for m := range item.members {
					if !d.members[m] {
						within = false
						break
					}
				}
			}
			if sameName || within {
				parts = append(parts, HealthPart{ID: d.id, Name: d.name})
			}
		}
		if len(parts) == 0 {
			continue
		}
		issue.Count++
		if len(issue.Samples) < healthSamples {
			issue.Samples = append(issue.Samples, HealthSample{ID: item.id, Name: item.name, Parts: parts})
		}
	}
	return issue, nil
}

// dismissedKeys is the keys dismissed for one kind of health issue, read
// once for a check rather than looked up for every row it reads.
func (s *Store) dismissedKeys(kind string) map[string]bool {
	out := map[string]bool{}
	rows, err := s.DB.Query(`SELECT key FROM health_dismissed WHERE kind = ?`, kind)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var key string
		if rows.Scan(&key) == nil {
			out[key] = true
		}
	}
	return out
}
