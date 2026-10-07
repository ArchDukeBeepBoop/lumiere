package store

// Episode cards show their series' artwork, because episodes rarely have any of
// their own: of 105,826 images in this library only 3,521 are backdrops, and
// they hang off series and films. Jellyfin emits ParentBackdropItemId,
// ParentBackdropImageTags and SeriesPrimaryImageTag on 92–100% of items for
// exactly this reason, and without them every episode card is a grey rectangle.
//
// Resolved in one query for the whole page, keyed on the series ids the page
// happens to mention — typically a handful even on a 200-row page of episodes.
func (s *Store) hydrateParentArt(items []Item) error {
	wanted := map[string]bool{}
	for _, it := range items {
		if it.SeriesID != "" {
			wanted[it.SeriesID] = true
		}
	}
	if len(wanted) == 0 {
		return nil
	}

	ids := make([]any, 0, len(wanted))
	for id := range wanted {
		ids = append(ids, id)
	}
	rows, err := s.DB.Query(
		`SELECT item_id, kind, tag FROM image
		 WHERE item_id IN (`+placeholders(len(ids))+`)
		   AND kind IN ('Primary','Backdrop')
		 ORDER BY idx`, ids...)
	if err != nil {
		return err
	}
	defer rows.Close()

	primary := map[string]string{}
	backdrops := map[string][]string{}
	for rows.Next() {
		var id, kind, tag string
		if err := rows.Scan(&id, &kind, &tag); err != nil {
			return err
		}
		if kind == "Backdrop" {
			backdrops[id] = append(backdrops[id], tag)
			continue
		}
		if _, seen := primary[id]; !seen {
			primary[id] = tag
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for i := range items {
		it := &items[i]
		if it.SeriesID == "" {
			continue
		}
		it.SeriesPrimaryImageTag = primary[it.SeriesID]
		if tags := backdrops[it.SeriesID]; len(tags) > 0 {
			// The id travels with the tags: the client builds an image URL from
			// both, and a tag without the item it belongs to is unusable.
			it.ParentBackdropItemID = it.SeriesID
			it.ParentBackdropTags = tags
		}
	}
	return nil
}
