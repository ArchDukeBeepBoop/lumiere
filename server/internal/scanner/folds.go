package scanner

import (
	"database/sql"
	"fmt"
	"log/slog"
	"path/filepath"
	"strings"

	"lumiere-server/internal/store"
)

// foldEpisodeFilms turns films that are really episodes back into a show.
//
// The scanner filed `Adult/Otome Juurin Yuugi/… Episode 2.mp4` as a film
// called "Otome Juurin Yuugi": a file two levels deep with no season folder
// read as a movie in its own folder. televisionFolder fixes that for new
// files; this fixes the rows already written. The rule is the library's:
// a folder in a library declared as shows is a show, one file or forty.
//
// Television libraries only. In a film library two files in one folder are
// two versions of the same film, which is what Jellyfin models them as.
func foldEpisodeFilms(db *sql.DB, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT film.id, film.path, film.library_id
		FROM item film
		WHERE film.type = 'Movie' AND film.path IS NOT NULL
		  AND film.extra_type IS NULL AND film.is_folder = 0
		  AND EXISTS (
			SELECT 1 FROM library_folder lf
			JOIN item v ON v.id = lf.view_id
			WHERE lf.folder_id = film.library_id AND v.collection_type = 'tvshows'
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

	folded := 0
	for _, f := range films {
		// Every film in a television library is an episode of the show its
		// folder names — one file or forty. The sibling count used to gate
		// this and left a one-episode series catalogued as a movie.
		season, episode, numbered := store.ParseEpisodeOnly(f.path)
		if !numbered {
			season = 1
			episode = episodeFromName(strings.TrimSuffix(filepath.Base(f.path), filepath.Ext(f.path)))
		}
		dir := filepath.Dir(f.path)
		series, year := CleanTitle(filepath.Base(dir))
		layout := Layout{
			Kind: KindEpisode, Series: series, SeriesPath: dir,
			Season: season, Episode: episode, Title: series, Year: year,
		}
		if err := foldOne(db, f.id, f.path, f.library, layout); err != nil {
			log.Info("repair: could not fold film into show", "path", f.path, "error", err)
			continue
		}
		folded++
	}
	if folded > 0 {
		log.Info("repair: folded films into their shows", "episodes", folded)
	}
	return folded, nil
}

func foldOne(db *sql.DB, id, path, libraryID string, layout Layout) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	seriesID, err := ensureSeries(tx, libraryID, layout)
	if err != nil {
		return err
	}
	seasonID, err := ensureSeason(tx, libraryID, seriesID, layout)
	if err != nil {
		return err
	}
	name := displayName(Found{Path: path, Layout: layout})
	var index any
	if layout.Episode > 0 {
		index = layout.Episode
		name = fmt.Sprintf("Episode %d", layout.Episode)
	}
	_, err = tx.Exec(`
		UPDATE item SET type = 'Episode', name = ?, sort_name = ?,
		    parent_id = ?, series_id = ?, parent_index_number = ?, index_number = ?,
		    production_year = NULL
		WHERE id = ?`,
		name, name, seasonID, seriesID, layout.Season, index, id)
	if err != nil {
		return err
	}
	return tx.Commit()
}

// restoreSpecials undoes the Clip stamp on episodes in a Specials folder.
//
// The reverse of reclassifyExtras, for the one folder name that was on the
// extras list and should not have been: Specials is a season. A row is put
// back only where the rules *now* say content — a genuine creditless opening
// sitting in a Specials folder keeps its type from its own name — and the
// season it sits under is renamed to what Jellyfin calls it, at index 0, so
// the client draws it where specials go.
func restoreSpecials(db *sql.DB, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT i.id, i.path, COALESCE(f.path, ''), COALESCE(i.parent_id, '')
		FROM item i
		LEFT JOIN item f ON f.id = i.library_id
		WHERE i.extra_type = 'Clip' AND i.path IS NOT NULL
		  AND i.type IN ('Episode', 'Video')
		  AND (i.path LIKE '%/Specials/%' OR i.path LIKE '%/Special/%')`)
	if err != nil {
		return 0, err
	}
	type row struct{ id, path, root, parent string }
	var candidates []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.path, &r.root, &r.parent); err != nil {
			rows.Close()
			return 0, err
		}
		candidates = append(candidates, r)
	}
	rows.Close()

	restored := 0
	for _, r := range candidates {
		if r.root == "" || ExtraType(r.root, r.path) != "" {
			continue
		}
		if _, err := db.Exec(`UPDATE item SET extra_type = NULL WHERE id = ?`, r.id); err != nil {
			return restored, err
		}
		if r.parent != "" {
			db.Exec(`
				UPDATE item SET name = 'Specials', sort_name = 'Specials', index_number = 0
				WHERE id = ? AND type = 'Season' AND (index_number IS NULL OR index_number = 0)`,
				r.parent)
		}
		restored++
	}
	if restored > 0 {
		log.Info("repair: restored specials filed as clips", "episodes", restored)
	}
	return restored, nil
}

// relinkSeasonExtras gives season-nested supplements their season.
//
// `Show/Season 3/Extras/NCOP1.mkv` was filed as a loose video of no show,
// because the layout read only the folder beside the file. The creditless
// opening of season 3 is part of season 3 — it is what plays before those
// episodes — and a row with no series cannot sit anywhere. Rebuilt from the
// path: the season folder names the season, the folder above it the show.
func RelinkSeasonExtras(db *sql.DB, roots []Root, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT id, path, COALESCE(library_id, ''), COALESCE(extra_type, '') FROM item
		WHERE is_folder = 0 AND path IS NOT NULL
		  AND type IN ('Video', 'Movie')
		  AND (series_id IS NULL OR series_id = '')`)
	if err != nil {
		return 0, err
	}
	type loose struct{ id, path, library, extra string }
	var files []loose
	for rows.Next() {
		var f loose
		if err := rows.Scan(&f.id, &f.path, &f.library, &f.extra); err != nil {
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
		layout := Describe(root.Path, f.path)
		if layout.Kind != KindEpisode {
			continue
		}
		extra := ExtraType(root.Path, f.path)
		if extra == "" && f.extra != "" {
			// Jellyfin's numeric codes — "0" is Clip — become the word.
			extra = "Clip"
		}
		tx, err := db.Begin()
		if err != nil {
			return linked, err
		}
		seriesID, err := ensureSeries(tx, root.LibraryID, layout)
		if err != nil {
			tx.Rollback()
			continue
		}
		seasonID, err := ensureSeason(tx, root.LibraryID, seriesID, layout)
		if err != nil {
			tx.Rollback()
			continue
		}
		var season any
		if layout.Season >= 0 {
			season = layout.Season
		}
		_, err = tx.Exec(`
			UPDATE item SET type = 'Episode', parent_id = ?, series_id = ?, season_id = ?,
			    parent_index_number = ?, extra_type = ?, library_id = ?
			WHERE id = ?`,
			seasonID, seriesID, seasonID, season, nullString(extra), root.LibraryID, f.id)
		if err != nil {
			tx.Rollback()
			continue
		}
		if tx.Commit() == nil {
			linked++
		}
	}
	if linked > 0 {
		log.Info("repair: gave season extras their season", "files", linked)
	}
	return linked, nil
}
