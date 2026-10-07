package scanner

import (
	"database/sql"
	"path/filepath"
	"strings"
)

// ensureFolders makes the Folder rows between a library root and a file, and
// returns the id of the one the file sits in.
//
// The scanner wrote every loose file with no parent at all, so a clip added to
// `3D/TV/Skyline/` appeared at the library's root, beside the folders, rather
// than inside the one it was in — and the folder went on looking as it had
// before the file arrived. Jellyfin models a folder library as a tree of
// Folder items with the files hung off the deepest one; this builds the same
// tree from the path, matching an existing folder by its path so the ones the
// import made are reused rather than duplicated.
//
// `stopBefore` is the number of trailing directories to leave out. A film's
// own folder is the film, not a container — `Movies/Blade Runner (1982)/` has
// no Folder row in Jellyfin's tree — so a movie passes 1; a loose clip passes
// 0 and gets every directory above it.
func ensureFolders(tx *sql.Tx, libraryID, root, filePath string, stopBefore int) (string, error) {
	relative, err := filepath.Rel(root, filepath.Dir(filePath))
	if err != nil || relative == "." || strings.HasPrefix(relative, "..") {
		return libraryID, nil
	}
	parts := strings.Split(filepath.ToSlash(relative), "/")
	if stopBefore > 0 && len(parts) >= stopBefore {
		parts = parts[:len(parts)-stopBefore]
	}

	parentID := libraryID
	dir := root
	for _, part := range parts {
		dir = filepath.Join(dir, part)
		var id string
		err := tx.QueryRow(
			`SELECT id FROM item WHERE type = 'Folder' AND path = ?`, dir,
		).Scan(&id)
		if err == sql.ErrNoRows {
			id = ItemID(dir)
			_, err = tx.Exec(`
				INSERT INTO item (id, type, name, sort_name, library_id, parent_id, path, is_folder, date_created)
				VALUES (?, 'Folder', ?, ?, ?, ?, ?, 1, ?)
				ON CONFLICT(id) DO NOTHING`,
				id, part, part, libraryID, parentID, dir, folderDate(dir))
		}
		if err != nil {
			return "", err
		}
		parentID = id
	}
	return parentID, nil
}

// relinkLooseFiles gives a parent to every file that has none.
//
// The repair half of ensureFolders, for the rows written before it existed —
// and for the sixty-four files the Jellyfin import left with no library at
// all, which no view could ever have listed. A file's path says which root it
// is under; that is enough to file it.
func RelinkLooseFiles(db *sql.DB, roots []Root) (int, error) {
	rows, err := db.Query(`
		SELECT id, path, type FROM item
		WHERE is_folder = 0 AND path IS NOT NULL AND path <> ''
		  AND type IN ('Video', 'Movie')
		  AND (parent_id IS NULL OR parent_id = '' OR library_id IS NULL OR library_id = '')`)
	if err != nil {
		return 0, err
	}
	type loose struct{ id, path, kind string }
	var files []loose
	for rows.Next() {
		var f loose
		if err := rows.Scan(&f.id, &f.path, &f.kind); err != nil {
			rows.Close()
			return 0, err
		}
		files = append(files, f)
	}
	rows.Close()

	linked := 0
	for _, f := range files {
		var root Root
		for _, candidate := range roots {
			if strings.HasPrefix(f.path, candidate.Path+string(filepath.Separator)) {
				root = candidate
				break
			}
		}
		if root.Path == "" {
			continue
		}
		stop := 0
		if f.kind == "Movie" {
			stop = 1
		}
		tx, err := db.Begin()
		if err != nil {
			return linked, err
		}
		parent, err := ensureFolders(tx, root.LibraryID, root.Path, f.path, stop)
		if err == nil {
			_, err = tx.Exec(`UPDATE item SET parent_id = ?, library_id = ? WHERE id = ?`,
				parent, root.LibraryID, f.id)
		}
		if err != nil {
			tx.Rollback()
			continue
		}
		if err := tx.Commit(); err == nil {
			linked++
		}
	}
	return linked, nil
}
