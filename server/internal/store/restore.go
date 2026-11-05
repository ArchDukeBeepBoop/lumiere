package store

import (
	"strings"
	"time"
)

// RestoreLibrary recreates a library under the id it had before, with its
// folders, and returns each folder's id by path.
//
// CreateLibrary mints a new id, which is right for a library someone is adding
// and wrong for one being put back: every app that synced the library holds the
// old id, and a new one reads to them as a library that vanished and a stranger
// that appeared. See internal/rebuild.
func (s *Store) RestoreLibrary(id, name, kind string, paths []string) (map[string]string, error) {
	name = strings.TrimSpace(name)
	if id == "" || name == "" || !LibraryKinds[kind] {
		return nil, ErrBadLibrary
	}
	tx, err := s.DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`INSERT INTO item (id, type, name, sort_name, parent_id, is_folder, collection_type, date_created)
		VALUES (?, 'CollectionFolder', ?, ?, ?, 1, ?, ?)`,
		id, name, strings.ToLower(name), viewRoot, nullable(kind), time.Now().UTC().Format(time.RFC3339)); err != nil {
		return nil, err
	}
	folders := map[string]string{}
	for _, path := range paths {
		if err := addFolder(tx, id, path); err != nil {
			return nil, err
		}
		folders[path] = stableID("lumiere:folder:" + id + ":" + path)
	}
	return folders, tx.Commit()
}
