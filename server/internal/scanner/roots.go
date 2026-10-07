package scanner

import (
	"os"
	"strings"

	"lumiere-server/internal/store"
)

// RootsFrom reads the library roots out of the database.
//
// The physical folders, which already carry their real paths — the import wrote
// them, and they are the one piece of Jellyfin's knowledge this scanner still
// needs: where the media is. A library added in Jellyfin after the last import
// is invisible until the next one, which is the remaining dependency and is
// worth stating plainly.
func RootsFrom(db *store.Store) ([]Root, error) {
	rows, err := db.DB.Query(`
		SELECT lf.folder_id, i.path, i.name
		FROM library_folder lf
		JOIN item i ON i.id = lf.folder_id
		WHERE i.path IS NOT NULL AND i.path <> ''
		ORDER BY i.name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var roots []Root
	for rows.Next() {
		var root Root
		if err := rows.Scan(&root.LibraryID, &root.Path, &root.Name); err != nil {
			return nil, err
		}
		// Jellyfin's own placeholders are not places. A Collections library is
		// filed under `%AppDataPath%/collections`, which is a token Jellyfin
		// expands at runtime and a path that has never existed — walking it
		// reported an error on every scan for a library with nothing on disk to
		// find.
		if strings.HasPrefix(root.Path, "%") {
			continue
		}
		roots = append(roots, root)
	}
	return roots, rows.Err()
}

// CountMissing is every catalogued media file no longer on disk.
//
// The whole catalogue, not one library: the per-library figure only counts what
// a walk could have found, so a row pointing at a path outside every current
// root — an old mount point, a library removed from Jellyfin — was invisible in
// exactly the case somebody is trying to diagnose.
//
// Stat per row, which on 43,000 files is a second or two against a warm cache
// and is why it runs once at the end of a scan rather than continuously.
func CountMissing(db *store.Store) (int, error) {
	rows, err := db.DB.Query(
		`SELECT path FROM item WHERE path IS NOT NULL AND path <> ''`)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	missing := 0
	for rows.Next() {
		var path string
		if err := rows.Scan(&path); err != nil {
			return 0, err
		}
		if !IsMedia(path) {
			continue
		}
		if _, err := os.Stat(path); err != nil {
			missing++
		}
	}
	return missing, rows.Err()
}
