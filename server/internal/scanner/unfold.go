package scanner

import (
	"database/sql"
	"log/slog"
	"path/filepath"
	"strings"
)

// UnfoldFolderFilms is plainFolderFile for the rows already written.
//
// A film in a plain folder library is a clip the film rule mis-filed: it took
// its folder's name and its folder's place. Each becomes a Video named by its
// file, under a Folder row for the directory it sits in — the tree
// ensureFolders would have built had the rule been there.
func UnfoldFolderFilms(db *sql.DB, roots []Root, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT film.id, film.path, film.library_id
		FROM item film
		WHERE film.type = 'Movie' AND film.path IS NOT NULL
		  AND film.extra_type IS NULL AND film.is_folder = 0
		  AND EXISTS (
			SELECT 1 FROM library_folder lf
			JOIN item v ON v.id = lf.view_id
			WHERE lf.folder_id = film.library_id
			  AND COALESCE(v.collection_type, '') IN ('', 'homevideos', 'folders', 'mixed')
		  )`)
	if err != nil {
		return 0, err
	}
	type film struct{ id, path, library string }
	var films []film
	for rows.Next() {
		var f film
		if err := rows.Scan(&f.id, &f.path, &f.library); err != nil {
			rows.Close()
			return 0, err
		}
		films = append(films, f)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	rootOf := map[string]string{}
	for _, r := range roots {
		rootOf[r.LibraryID] = r.Path
	}
	unfolded := 0
	for _, f := range films {
		root, ok := rootOf[f.library]
		if !ok {
			continue
		}
		tx, err := db.Begin()
		if err != nil {
			return unfolded, err
		}
		parentID, err := ensureFolders(tx, f.library, root, f.path, 0)
		if err == nil {
			title, _ := CleanTitle(strings.TrimSuffix(filepath.Base(f.path), filepath.Ext(f.path)))
			_, err = tx.Exec(`
				UPDATE item SET type = 'Video', name = ?, sort_name = ?, parent_id = ?
				WHERE id = ?`, title, title, parentID, f.id)
		}
		if err != nil {
			tx.Rollback()
			log.Info("repair: could not unfold film into its folder", "path", f.path, "error", err)
			continue
		}
		if err := tx.Commit(); err != nil {
			return unfolded, err
		}
		unfolded++
	}
	if unfolded > 0 {
		log.Info("repair: unfolded films into their folders", "videos", unfolded)
	}
	return unfolded, nil
}
