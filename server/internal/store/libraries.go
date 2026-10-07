package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"path/filepath"
	"strings"
	"time"
)

// Libraries as a person manages them: a name, a kind, and the folders on disk
// that fill it.
//
// A library is two kinds of row, as the importer left them: the view the apps
// list (a CollectionFolder with the kind on it) and one physical Folder per
// place on disk, whose id every file inside carries as its library_id. The
// library_folder table joins them. A fresh server has neither until someone
// adds a library here, which is what the first-run guide does.

// LibraryKinds are the kinds a library may declare. "" is a plain folder
// library: folders stay folders and files keep their names.
var LibraryKinds = map[string]bool{
	"movies": true, "tvshows": true, "music": true, "homevideos": true, "mixed": true, "": true,
}

// ErrBadLibrary is a request the store refuses: an unknown kind, an empty
// name, a path that is not an absolute folder, or one already in a library.
var ErrBadLibrary = errors.New("bad library request")

// LibraryFolder is one place on disk feeding a library.
type LibraryFolder struct {
	ID   string `json:"Id"`
	Path string `json:"Path"`
}

// Library is one library with its folders.
type Library struct {
	ID      string          `json:"Id"`
	Name    string          `json:"Name"`
	Kind    string          `json:"CollectionType"`
	Folders []LibraryFolder `json:"Folders"`
	Items   int             `json:"ItemCount"`
}

// The parents new rows hang from. Imported libraries keep the importer's own.
var (
	viewRoot   = stableID("lumiere:views")
	folderRoot = stableID("lumiere:folders")
)

func stableID(key string) string {
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:16])
}

// ListLibraries is every library and its folders, by name.
func (s *Store) ListLibraries() ([]Library, error) {
	rows, err := s.DB.Query(`
		SELECT v.id, v.name, COALESCE(v.collection_type, ''), COALESCE(f.id, ''), COALESCE(f.path, ''),
		       (SELECT count(*) FROM item c WHERE c.library_id = f.id AND c.is_folder = 0)
		FROM item v
		LEFT JOIN library_folder lf ON lf.view_id = v.id
		LEFT JOIN item f ON f.id = lf.folder_id
		WHERE v.type = 'CollectionFolder' AND COALESCE(v.collection_type, '') <> 'livetv'
		ORDER BY v.name COLLATE NOCASE, f.path`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Library
	for rows.Next() {
		var id, name, kind, folder, path string
		var count int
		if err := rows.Scan(&id, &name, &kind, &folder, &path, &count); err != nil {
			return nil, err
		}
		if len(out) == 0 || out[len(out)-1].ID != id {
			out = append(out, Library{ID: id, Name: name, Kind: kind, Folders: []LibraryFolder{}})
		}
		// Jellyfin's placeholders (%AppDataPath%) are not places anyone chose.
		if folder != "" && !strings.HasPrefix(path, "%") {
			last := &out[len(out)-1]
			last.Folders = append(last.Folders, LibraryFolder{ID: folder, Path: path})
			last.Items += count
		}
	}
	return out, rows.Err()
}

// CreateLibrary adds a library with its folders and returns its id.
func (s *Store) CreateLibrary(name, kind string, paths []string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" || !LibraryKinds[kind] {
		return "", ErrBadLibrary
	}
	id := stableID("lumiere:library:" + name + ":" + time.Now().String())
	now := time.Now().UTC().Format(time.RFC3339)
	tx, err := s.DB.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`INSERT INTO item (id, type, name, sort_name, parent_id, is_folder, collection_type, date_created)
		VALUES (?, 'CollectionFolder', ?, ?, ?, 1, ?, ?)`,
		id, name, strings.ToLower(name), viewRoot, nullable(kind), now); err != nil {
		return "", err
	}
	for _, path := range paths {
		if err := addFolder(tx, id, path); err != nil {
			return "", err
		}
	}
	return id, tx.Commit()
}

// AddLibraryFolder adds one more place on disk to a library.
func (s *Store) AddLibraryFolder(libraryID, path string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var n int
	tx.QueryRow(`SELECT count(*) FROM item WHERE id = ? AND type = 'CollectionFolder'`, libraryID).Scan(&n)
	if n == 0 {
		return ErrNoItem
	}
	if err := addFolder(tx, libraryID, path); err != nil {
		return err
	}
	return tx.Commit()
}

func addFolder(tx *sql.Tx, viewID, path string) error {
	path = filepath.Clean(strings.TrimSpace(path))
	if !filepath.IsAbs(path) {
		return ErrBadLibrary
	}
	// One folder, one library: the files inside carry a single library_id.
	var taken int
	tx.QueryRow(`SELECT count(*) FROM library_folder lf JOIN item f ON f.id = lf.folder_id WHERE f.path = ?`, path).Scan(&taken)
	if taken > 0 {
		return ErrBadLibrary
	}
	id := stableID("lumiere:folder:" + viewID + ":" + path)
	if _, err := tx.Exec(`INSERT OR IGNORE INTO item (id, type, name, sort_name, parent_id, library_id, path, is_folder, date_created)
		VALUES (?, 'Folder', ?, ?, ?, ?, ?, 1, ?)`,
		id, filepath.Base(path), strings.ToLower(filepath.Base(path)), folderRoot, id, path,
		time.Now().UTC().Format(time.RFC3339)); err != nil {
		return err
	}
	_, err := tx.Exec(`INSERT OR IGNORE INTO library_folder (view_id, folder_id) VALUES (?, ?)`, viewID, id)
	return err
}

// UpdateLibrary renames a library or changes its kind; an empty name keeps it.
func (s *Store) UpdateLibrary(libraryID, name string, kind *string) error {
	if kind != nil && !LibraryKinds[*kind] {
		return ErrBadLibrary
	}
	if name = strings.TrimSpace(name); name != "" {
		if _, err := s.DB.Exec(`UPDATE item SET name = ?, sort_name = ? WHERE id = ? AND type = 'CollectionFolder'`,
			name, strings.ToLower(name), libraryID); err != nil {
			return err
		}
	}
	if kind != nil {
		_, err := s.DB.Exec(`UPDATE item SET collection_type = ? WHERE id = ? AND type = 'CollectionFolder'`,
			nullable(*kind), libraryID)
		return err
	}
	return nil
}

// RemoveLibraryFolder takes a folder out of a library and forgets what was
// catalogued from it. Nothing on disk is touched.
func (s *Store) RemoveLibraryFolder(libraryID, folderID string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := dropFolder(tx, libraryID, folderID); err != nil {
		return err
	}
	return tx.Commit()
}

// RemoveLibrary removes a library, its folders and its catalogue.
func (s *Store) RemoveLibrary(libraryID string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	rows, err := tx.Query(`SELECT folder_id FROM library_folder WHERE view_id = ?`, libraryID)
	if err != nil {
		return err
	}
	var folders []string
	for rows.Next() {
		var f string
		rows.Scan(&f)
		folders = append(folders, f)
	}
	rows.Close()
	for _, f := range folders {
		if err := dropFolder(tx, libraryID, f); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(`DELETE FROM item WHERE id = ? AND type = 'CollectionFolder'`, libraryID); err != nil {
		return err
	}
	return tx.Commit()
}

func dropFolder(tx *sql.Tx, viewID, folderID string) error {
	res, err := tx.Exec(`DELETE FROM library_folder WHERE view_id = ? AND folder_id = ?`, viewID, folderID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNoItem
	}
	for _, stmt := range []string{
		`DELETE FROM image WHERE item_id IN (SELECT id FROM item WHERE library_id = ?)`,
		`DELETE FROM stream WHERE item_id IN (SELECT id FROM item WHERE library_id = ?)`,
		`DELETE FROM item_value WHERE item_id IN (SELECT id FROM item WHERE library_id = ?)`,
		`DELETE FROM item WHERE library_id = ?`,
	} {
		if _, err := tx.Exec(stmt, folderID); err != nil {
			return err
		}
	}
	return nil
}
