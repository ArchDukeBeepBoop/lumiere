// Package rebuild puts a lost library back together from a Lumiere app's cache.
//
// The server's database is the only copy of the watch history, and on
// 2026-10-25 it and every backup beside it were deleted. What survived was the
// Mac app's own cache: every item it had synced, with its id, its path on disk
// and the watch state the server had last reported. This reads that cache into
// a fresh database.
//
// Ids are kept, not re-derived. The apps hold them — the Mac's cache, the TV's,
// the phone's — so an item restored under its old id is one they already know,
// and a scan afterwards matches it by path and leaves it alone.
//
// What the cache never held cannot come back: artwork files, chapters, track
// lists (the stream pass refills those from the files), collections, people,
// and the account itself, which the first-run guide makes again.
package rebuild

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// Report is what a rebuild did, in counts only: the library is private.
type Report struct {
	Libraries, Folders, Items, Skipped int
	Watched, InProgress, Favorites     int
}

// Options are the parts of a rebuild that are not in the cache.
type Options struct {
	// PrivateLibraries are the library ids the app had marked private. The
	// server's own list went with the database, and a private library served
	// as an ordinary one for even a minute is the failure that matters most.
	PrivateLibraries []string
	// Stat gives a file's size; nil skips it. Real runs pass os.Stat.
	Stat func(path string) (int64, bool)
}

// StatFile is the Stat a real rebuild uses.
func StatFile(path string) (int64, bool) {
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return 0, false
	}
	return info.Size(), true
}

type library struct{ id, name, kind string }

type cached struct {
	id, typ, name, sortName                  string
	originalTitle, overview                  sql.NullString
	parentID, seriesID, seriesName, seasonID sql.NullString
	index, parentIndex, year                 sql.NullInt64
	premiere, created, rating                sql.NullString
	community                                sql.NullFloat64
	ticks                                    sql.NullInt64
	genres, studios, path, extra, libraryID  sql.NullString
	album, albumArtist, artists              sql.NullString
	isFolder                                 bool
}

// FromClientCache reads the app's cache at cachePath into db, which must be a
// fresh database: one transaction for the items, so a rebuild that fails part
// way leaves nothing half done.
func FromClientCache(cachePath string, db *store.Store, opt Options) (Report, error) {
	var rep Report
	cache, err := sql.Open("sqlite", "file:"+cachePath+"?immutable=1")
	if err != nil {
		return rep, err
	}
	defer cache.Close()

	libs, err := readLibraries(cache)
	if err != nil {
		return rep, err
	}
	items, err := readItems(cache, libs)
	if err != nil {
		return rep, err
	}
	paths := map[string]string{}
	for _, it := range items {
		if it.path.Valid && strings.HasPrefix(it.path.String, "/") {
			paths[dirOf(it)] = it.libraryID.String
		}
	}
	roots := Roots(paths)

	folderOf := map[string]map[string]string{} // library → root → folder id
	for _, lib := range libs {
		folders, err := db.RestoreLibrary(lib.id, lib.name, lib.kind, roots[lib.id])
		if err != nil {
			return rep, fmt.Errorf("library %s: %w", lib.id, err)
		}
		folderOf[lib.id] = folders
		rep.Libraries++
		rep.Folders += len(folders)
	}

	tx, err := db.DB.Begin()
	if err != nil {
		return rep, err
	}
	defer tx.Rollback()
	kept := map[string]bool{}
	for _, it := range items {
		kept[it.id] = true
	}
	for _, it := range items {
		folder := folderFor(folderOf[it.libraryID.String], it.path.String)
		if folder == "" || (it.typ == "Folder" && isRoot(roots[it.libraryID.String], it.path.String)) {
			rep.Skipped++
			continue
		}
		if err := insertItem(tx, it, folder, kept, opt.Stat); err != nil {
			return rep, fmt.Errorf("item %s: %w", it.id, err)
		}
		rep.Items++
	}
	if err := copyWatchState(tx, cache, &rep); err != nil {
		return rep, err
	}
	if len(opt.PrivateLibraries) > 0 {
		if _, err := tx.Exec(`INSERT OR REPLACE INTO meta (key, value) VALUES ('private_libraries', ?)`,
			strings.Join(opt.PrivateLibraries, ",")); err != nil {
			return rep, err
		}
	}
	return rep, tx.Commit()
}

// readLibraries is every library the server served. The app's own "Opened
// Files" shelf is not one, and Collections and Playlists are made by the
// server rather than filled from a folder.
func readLibraries(cache *sql.DB) ([]library, error) {
	rows, err := cache.Query(`SELECT id, name, COALESCE(collectionType, '') FROM library
		WHERE id NOT LIKE 'locallib:%' AND COALESCE(collectionType, '') NOT IN ('boxsets', 'playlists')
		ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []library
	for rows.Next() {
		var l library
		if err := rows.Scan(&l.id, &l.name, &l.kind); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

func readItems(cache *sql.DB, libs []library) ([]cached, error) {
	ids := make([]string, len(libs))
	args := make([]any, len(libs))
	for i, l := range libs {
		ids[i], args[i] = "?", l.id
	}
	rows, err := cache.Query(`SELECT id, type, name, sortName, originalTitle, overview,
		parentId, seriesId, seriesName, seasonId, indexNumber, parentIndexNumber, productionYear,
		premiereDate, dateCreated, officialRating, communityRating, runTimeTicks,
		genres, studios, path, extraType, libraryId, album, albumArtist, artists, isFolder
		FROM item WHERE type <> 'BoxSet' AND libraryId IN (`+strings.Join(ids, ",")+`)
		ORDER BY isFolder DESC`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []cached
	for rows.Next() {
		var c cached
		if err := rows.Scan(&c.id, &c.typ, &c.name, &c.sortName, &c.originalTitle, &c.overview,
			&c.parentID, &c.seriesID, &c.seriesName, &c.seasonID, &c.index, &c.parentIndex, &c.year,
			&c.premiere, &c.created, &c.rating, &c.community, &c.ticks,
			&c.genres, &c.studios, &c.path, &c.extra, &c.libraryID,
			&c.album, &c.albumArtist, &c.artists, &c.isFolder); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func insertItem(tx *sql.Tx, it cached, folder string, kept map[string]bool, stat func(string) (int64, bool)) error {
	// A parent the rebuild does not have — Jellyfin's own folder rows, which
	// the app never synced — becomes the library folder itself.
	parent := it.parentID.String
	if !kept[parent] {
		parent = folder
	}
	var size, container any
	if !it.isFolder && it.path.Valid {
		if stat != nil {
			if n, ok := stat(it.path.String); ok {
				size = n
			}
		}
		if ext := strings.TrimPrefix(strings.ToLower(filepath.Ext(it.path.String)), "."); ext != "" {
			container = ext
		}
	}
	if _, err := tx.Exec(`INSERT INTO item (id, type, name, sort_name, original_title, overview,
		parent_id, library_id, series_id, series_name, season_id, index_number, parent_index_number,
		production_year, premiere_date, date_created, official_rating, community_rating, runtime_ticks,
		container, path, size, is_folder, extra_type, album, album_artist, artists)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
		it.id, it.typ, it.name, it.sortName, it.originalTitle, it.overview,
		parent, folder, it.seriesID, it.seriesName, it.seasonID, it.index, it.parentIndex,
		it.year, it.premiere, it.created, it.rating, it.community, it.ticks,
		container, it.path, size, it.isFolder, it.extra, it.album, it.albumArtist,
		pipes(it.artists)); err != nil {
		return err
	}
	for kind, list := range map[string]sql.NullString{"genre": it.genres, "studio": it.studios} {
		for _, v := range strings.Split(list.String, "\n") {
			if v = strings.TrimSpace(v); v != "" {
				if _, err := tx.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?,?,?)`,
					it.id, kind, v); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

// copyWatchState is the point of all this: what was watched, how far, and what
// was a favourite, for every item the rebuild put back.
func copyWatchState(tx *sql.Tx, cache *sql.DB, rep *Report) error {
	rows, err := cache.Query(`SELECT itemId, played, COALESCE(playCount, 0), COALESCE(playbackPositionTicks, 0),
		isFavorite, lastPlayedDate, updatedAt FROM userData
		WHERE played = 1 OR playbackPositionTicks > 0 OR isFavorite = 1 OR playCount > 0`)
	if err != nil {
		return err
	}
	defer rows.Close()
	now := time.Now().UTC().Format(time.RFC3339)
	for rows.Next() {
		var id string
		var played, favorite bool
		var count, ticks int64
		var last, updated sql.NullString
		if err := rows.Scan(&id, &played, &count, &ticks, &favorite, &last, &updated); err != nil {
			return err
		}
		if !updated.Valid {
			updated.String = now
		}
		res, err := tx.Exec(`INSERT INTO user_data (item_id, played, play_count, position_ticks,
			is_favorite, last_played, updated_at, source)
			SELECT ?, ?, ?, ?, ?, ?, ?, 'local' WHERE EXISTS (SELECT 1 FROM item WHERE id = ?)`,
			id, played, count, ticks, favorite, last, updated.String, id)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			continue
		}
		if played {
			rep.Watched++
		}
		if ticks > 0 {
			rep.InProgress++
		}
		if favorite {
			rep.Favorites++
		}
	}
	return rows.Err()
}
