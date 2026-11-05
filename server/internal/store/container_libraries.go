package store

import (
	"database/sql"
	"time"
)

// The Collections and Playlists libraries.
//
// Every other library is a folder on disk; these two are made by the server,
// and a library put back without them (2026-10-25) had 209 collections filed
// nowhere — invisible in the apps, with no Collections page and none of its
// settings. They are now ensured at every start: a view, its placeholder
// folder (a `%AppDataPath%` path, which the scanner and the library editor
// both skip), and every collection or playlist with no home filed into it.
//
// The ids are stable, or the ones a previous library used where meta records
// them (`collections_view_id`, `collections_folder_id`, and the playlists
// pair), so the apps' settings for the library — its place in the sidebar,
// its shelves — carry over.

type containerLibrary struct {
	kind, name, placeholder, itemType string
}

var containerLibraries = []containerLibrary{
	{"boxsets", "Collections", "%AppDataPath%/collections", "BoxSet"},
	{"playlists", "Playlists", "%AppDataPath%/playlists", "Playlist"},
}

// EnsureContainerLibraries makes both libraries if missing and homes strays.
// Returns how many collections and playlists it filed.
func (s *Store) EnsureContainerLibraries() (int, error) {
	homed := 0
	for _, c := range containerLibraries {
		folder, err := s.ensureContainerLibrary(c)
		if err != nil {
			return homed, err
		}
		res, err := s.DB.Exec(`UPDATE item SET parent_id = ?, library_id = ?
			WHERE type = ? AND COALESCE(parent_id, '') = ''
			  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = item.id AND v.kind = 'room:private')`,
			folder, folder, c.itemType)
		if err != nil {
			return homed, err
		}
		n, _ := res.RowsAffected()
		homed += int(n)
	}
	return homed, nil
}

// ensureContainerLibrary returns the library's folder id, making it if needed.
func (s *Store) ensureContainerLibrary(c containerLibrary) (string, error) {
	var folder string
	err := s.DB.QueryRow(`SELECT lf.folder_id FROM item v JOIN library_folder lf ON lf.view_id = v.id
		WHERE v.type = 'CollectionFolder' AND v.collection_type = ? LIMIT 1`, c.kind).Scan(&folder)
	if err == nil {
		return folder, nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	view, _ := s.Meta(c.kind + "_view_id")
	if view == "" {
		view = stableID("lumiere:view:" + c.kind)
	}
	folder, _ = s.Meta(c.kind + "_folder_id")
	if folder == "" {
		folder = stableID("lumiere:folder:" + c.kind)
	}
	now := time.Now().UTC().Format(time.RFC3339)
	tx, err := s.DB.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`INSERT OR IGNORE INTO item (id, type, name, sort_name, parent_id, is_folder, collection_type, date_created)
		VALUES (?, 'CollectionFolder', ?, ?, ?, 1, ?, ?)`, view, c.name, c.name, viewRoot, c.kind, now); err != nil {
		return "", err
	}
	if _, err := tx.Exec(`INSERT OR IGNORE INTO item (id, type, name, sort_name, parent_id, library_id, path, is_folder, collection_type, date_created)
		VALUES (?, 'Folder', ?, ?, ?, ?, ?, 1, ?, ?)`, folder, c.name, c.name, folderRoot, folder, c.placeholder, c.kind, now); err != nil {
		return "", err
	}
	if _, err := tx.Exec(`INSERT OR IGNORE INTO library_folder (view_id, folder_id) VALUES (?, ?)`, view, folder); err != nil {
		return "", err
	}
	return folder, tx.Commit()
}
