package store

import (
	"database/sql"
	"strings"
)

// hydrate fills in everything that does not live on the item row.
//
// One query per attribute per page, not per item. A 200-item page costs four
// statements here; doing it per row would cost 800, and the sync is 123 pages.
// Joining instead would multiply the page by genre count and make the LIMIT
// meaningless.
func (s *Store) hydrate(items []Item) error {
	if len(items) == 0 {
		return nil
	}
	byID := indexOf(items)
	in, args := idList(items)

	if err := s.hydrateValues(byID, in, args); err != nil {
		return err
	}
	if err := s.hydrateImages(byID, in, args); err != nil {
		return err
	}
	if err := s.hydrateUserData(byID, in, args); err != nil {
		return err
	}
	if err := s.hydrateUnplayed(byID, in, args); err != nil {
		return err
	}
	if err := s.hydrateCounts(byID, in, args); err != nil {
		return err
	}
	return s.hydrateParentArt(items)
}

func (s *Store) hydrateValues(byID map[string]*Item, in string, args []any) error {
	rows, err := s.DB.Query(
		`SELECT item_id, kind, value FROM item_value WHERE item_id IN (`+in+`)
		 ORDER BY value COLLATE NOCASE`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id, kind, value string
		if err := rows.Scan(&id, &kind, &value); err != nil {
			return err
		}
		it, ok := byID[id]
		if !ok {
			continue
		}
		switch kind {
		case "genre":
			it.Genres = append(it.Genres, value)
		case "tag":
			it.Tags = append(it.Tags, value)
		case "studio":
			// Studios are {Id, Name} on the wire and this server has no studio
			// items to point at, so the name doubles as the id. Lumiere shows the
			// name and never dereferences the id.
			it.Studios = append(it.Studios, Named{ID: value, Name: value})
		default:
			// provider:Tmdb, written by identify. Emitted so the client can ask
			// "what is this series, according to whom" without having to have
			// just identified it in the same session.
			if key, found := strings.CutPrefix(kind, "provider:"); found {
				if it.ProviderIDs == nil {
					it.ProviderIDs = map[string]string{}
				}
				it.ProviderIDs[key] = value
			}
		}
	}
	return rows.Err()
}

func (s *Store) hydrateImages(byID map[string]*Item, in string, args []any) error {
	rows, err := s.DB.Query(
		`SELECT item_id, kind, idx, tag FROM image WHERE item_id IN (`+in+`)
		 ORDER BY idx`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id, kind, tag string
		var idx int
		if err := rows.Scan(&id, &kind, &idx, &tag); err != nil {
			return err
		}
		it, ok := byID[id]
		if !ok {
			continue
		}
		if kind == "Backdrop" {
			// A list, and Lumiere reads only the first element — but the order
			// still decides which backdrop that is.
			it.Backdrops = append(it.Backdrops, tag)
			continue
		}
		if it.Images == nil {
			it.Images = map[string]string{}
		}
		// Only index 0 goes in ImageTags: the map is keyed by kind, so a second
		// Primary would overwrite the first and the client would cache-bust for
		// no reason.
		if _, seen := it.Images[kind]; !seen {
			it.Images[kind] = tag
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	// A track with no cover of its own shows its album's; an album with none
	// shows the first cover among its tracks. See MusicCoverFor.
	for id, it := range byID {
		if it.Type != "Audio" && it.Type != "MusicAlbum" {
			continue
		}
		if _, has := it.Images["Primary"]; has {
			continue
		}
		if ref, err := s.MusicCoverFor(id); err == nil {
			if it.Images == nil {
				it.Images = map[string]string{}
			}
			it.Images["Primary"] = ref.Tag
		}
	}
	return nil
}

func (s *Store) hydrateUserData(byID map[string]*Item, in string, args []any) error {
	rows, err := s.DB.Query(
		`SELECT item_id, played, play_count, position_ticks, is_favorite,
		        last_played, audio_index, subtitle_index
		 FROM user_data WHERE item_id IN (`+in+`)`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var u UserData
		var lastPlayed sql.NullString
		var audio, subtitle sql.NullInt64
		if err := rows.Scan(&id, &u.Played, &u.PlayCount, &u.PositionTicks,
			&u.IsFavorite, &lastPlayed, &audio, &subtitle); err != nil {
			return err
		}
		u.LastPlayed = lastPlayed.String
		if it, ok := byID[id]; ok {
			it.UserData = &u
			// Track choices live beside the watch state in the database but not
			// in UserItemData on the wire: they belong to the MediaSource.
			it.AudioIndex, it.SubtitleIndex = intPtr(audio), intPtr(subtitle)
		}
	}
	return rows.Err()
}

// hydrateUnplayed counts unwatched episodes under each series, season or folder.
//
// Required, not decorative: §5.2 marks UnplayedItemCount as needed on those
// types, it is emitted on 100% of them in the capture, and without it every show
// carries an unwatched badge forever (§9.6).
//
// Counted live rather than stored, because the number changes on every episode
// watched and a cached count that drifts is worse than one computed per page.
func (s *Store) hydrateUnplayed(byID map[string]*Item, in string, args []any) error {
	rows, err := s.DB.Query(`
		SELECT parent.id, COUNT(*)
		FROM item parent
		JOIN item child
		  ON (child.series_id = parent.id AND parent.type = 'Series')
		  OR (child.season_id = parent.id AND parent.type = 'Season')
		  OR (child.parent_id = parent.id AND parent.type IN ('Folder','BoxSet','CollectionFolder'))
		LEFT JOIN user_data u ON u.item_id = child.id
		WHERE parent.id IN (`+in+`)
		  AND child.is_folder = 0
		  AND child.extra_type IS NULL
		  AND COALESCE(u.played, 0) = 0
		GROUP BY parent.id`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var n int
		if err := rows.Scan(&id, &n); err != nil {
			return err
		}
		if it, ok := byID[id]; ok {
			count := n
			if it.UserData == nil {
				it.UserData = &UserData{}
			}
			it.UserData.UnplayedItemCount = &count
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if err := s.hydrateCollectionUnplayed(byID, in, args); err != nil {
		return err
	}
	// A series with every episode watched has no row above, and must still say
	// zero rather than omit the key — an absent count reads as "unknown", which
	// is what leaves the badge on.
	for _, it := range byID {
		if !hasChildren(it.Type) || (it.UserData != nil && it.UserData.UnplayedItemCount != nil) {
			continue
		}
		zero := 0
		if it.UserData == nil {
			it.UserData = &UserData{}
		}
		it.UserData.UnplayedItemCount = &zero
	}
	return nil
}
