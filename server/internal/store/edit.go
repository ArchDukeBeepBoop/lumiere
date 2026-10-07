package store

import (
	"database/sql"
	"strings"
)

// ItemEdit is what a hand-made edit may change.
//
// Jellyfin's `POST /Items/{id}` takes the whole item and replaces it, which is
// why the client reads the item first and posts it back with the edited keys
// changed. This server takes the same body and writes only the fields that a
// person can have meant to edit; everything else in the payload is the item
// describing itself, not an instruction.
type ItemEdit struct {
	Name            *string
	OriginalTitle   *string
	SortName        *string
	Overview        *string
	ProductionYear  *int
	OfficialRating  *string
	CommunityRating *float64
	IndexNumber     *int
	ParentIndex     *int
	Album           *string
	AlbumArtist     *string
	Genres          []string
	Studios         []string
	Tags            []string
	// LockedFields are the ones a refresh must leave alone, in Jellyfin's
	// vocabulary: Name, Overview, Genres, Studios, Tags, OfficialRating.
	LockedFields []string
	LockAll      bool
}

// ApplyEdit writes an edit, and remembers what was locked.
//
// Locks live in item_value under a `lock:` kind — the same table provider ids
// use — so the metadata pass can ask "is this field locked" with one query
// and no new column. `lock:*` is every field.
func (s *Store) ApplyEdit(itemID string, edit ItemEdit) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	set := func(column string, value any) error {
		_, err := tx.Exec(`UPDATE item SET `+column+` = ? WHERE id = ?`, value, itemID)
		return err
	}
	if edit.Name != nil {
		// Only a *changed* name moves the sort name. The artwork picker posts
		// the whole item back to lock it, name included and unchanged; a
		// sort name somebody set by hand must survive that.
		var current string
		tx.QueryRow(`SELECT name FROM item WHERE id = ?`, itemID).Scan(&current)
		if err := set("name", *edit.Name); err != nil {
			return err
		}
		if edit.SortName == nil && *edit.Name != current {
			if err := set("sort_name", *edit.Name); err != nil {
				return err
			}
		}
	}
	if edit.SortName != nil {
		if err := set("sort_name", *edit.SortName); err != nil {
			return err
		}
	}
	for column, value := range map[string]*string{
		"original_title":  edit.OriginalTitle,
		"overview":        edit.Overview,
		"official_rating": edit.OfficialRating,
		"album":           edit.Album,
		"album_artist":    edit.AlbumArtist,
	} {
		if value != nil {
			if err := set(column, *value); err != nil {
				return err
			}
		}
	}
	for column, value := range map[string]*int{
		"production_year":     edit.ProductionYear,
		"index_number":        edit.IndexNumber,
		"parent_index_number": edit.ParentIndex,
	} {
		if value != nil {
			if err := set(column, *value); err != nil {
				return err
			}
		}
	}
	if edit.CommunityRating != nil {
		if err := set("community_rating", *edit.CommunityRating); err != nil {
			return err
		}
	}

	// Lists are replaced, not merged: the sheet shows the whole list and
	// posts the whole list, so what is absent was removed.
	for kind, values := range map[string][]string{
		"genre": edit.Genres, "studio": edit.Studios, "tag": edit.Tags,
	} {
		if values == nil {
			continue
		}
		if err := replaceValues(tx, itemID, kind, values); err != nil {
			return err
		}
	}

	locks := edit.LockedFields
	if edit.LockAll {
		locks = []string{"*"}
	}
	if edit.LockedFields != nil || edit.LockAll {
		var named []string
		for _, lock := range locks {
			named = append(named, "lock:"+strings.ToLower(lock))
		}
		if err := replaceValues(tx, itemID, "lock", named); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func replaceValues(tx *sql.Tx, itemID, kind string, values []string) error {
	if kind == "lock" {
		// Locks are stored as their own kinds — `lock:name` — so the
		// "replace everything of this kind" below has to match the prefix.
		if _, err := tx.Exec(
			`DELETE FROM item_value WHERE item_id = ? AND kind LIKE 'lock:%'`, itemID,
		); err != nil {
			return err
		}
		for _, value := range values {
			if _, err := tx.Exec(
				`INSERT OR REPLACE INTO item_value (item_id, kind, value) VALUES (?, ?, '1')`,
				itemID, value,
			); err != nil {
				return err
			}
		}
		return nil
	}
	if _, err := tx.Exec(
		`DELETE FROM item_value WHERE item_id = ? AND kind = ?`, itemID, kind,
	); err != nil {
		return err
	}
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, err := tx.Exec(
			`INSERT OR REPLACE INTO item_value (item_id, kind, value) VALUES (?, ?, ?)`,
			itemID, kind, value,
		); err != nil {
			return err
		}
	}
	return nil
}

// IsLocked says whether a refresh may touch a field. Field names are Jellyfin's.
func (s *Store) IsLocked(itemID, field string) bool {
	var n int
	err := s.DB.QueryRow(`
		SELECT count(*) FROM item_value
		WHERE item_id = ? AND (kind = 'lock:*' OR kind = ?)`,
		itemID, "lock:"+strings.ToLower(field)).Scan(&n)
	return err == nil && n > 0
}
