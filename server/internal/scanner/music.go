package scanner

import (
	"context"
	"database/sql"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// Music, found on the disk rather than only through the Jellyfin import.
//
// The video scan left music out on purpose — the first version counted every
// track as missing — so an album copied in reached Lumiere only once Jellyfin
// had scanned it and the import had run. This walks a music library on its
// own terms: a track is filed under its album, the album under the library,
// and artists are matched by name, the way the import left them. Matched to
// what is already here by path, so nothing the import made is written twice.

var audioExtensions = map[string]bool{
	".mp3": true, ".flac": true, ".m4a": true, ".aac": true, ".ogg": true,
	".opus": true, ".wav": true, ".aiff": true, ".aif": true, ".wma": true, ".alac": true,
}

// IsAudio says whether a path is a track this pass handles.
func IsAudio(path string) bool { return audioExtensions[strings.ToLower(filepath.Ext(path))] }

// MusicResult is what one music library's pass did.
type MusicResult struct {
	Files, Added, Moved, Removed int
}

// ScanMusic finds tracks added, moved and removed in one music library.
func (s *Scanner) ScanMusic(libraryID, root string) (MusicResult, error) {
	var result MusicResult
	if info, err := os.Stat(root); err != nil || !info.IsDir() {
		return result, fs.ErrNotExist
	}
	known := map[string]string{} // path → id
	rows, err := s.Store.DB.Query(`SELECT id, path FROM item WHERE library_id = ? AND type = 'Audio'
		AND path IS NOT NULL AND path <> ''`, libraryID)
	if err != nil {
		return result, err
	}
	for rows.Next() {
		var id, path string
		rows.Scan(&id, &path)
		known[path] = id
	}
	rows.Close()
	// A track taken out by hand stays out.
	removed := map[string]bool{}
	if rows, err := s.Store.DB.Query(`SELECT json_extract(row, '$.path') FROM removed_item
		WHERE json_extract(row, '$.library_id') = ? AND json_extract(row, '$.path') IS NOT NULL`, libraryID); err == nil {
		for rows.Next() {
			var p string
			rows.Scan(&p)
			removed[p] = true
		}
		rows.Close()
	}

	var fresh []Found
	seen := map[string]bool{}
	filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			if entry != nil && entry.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if entry.IsDir() {
			if path != root && skipDir(entry.Name()) {
				return fs.SkipDir
			}
			return nil
		}
		if !IsAudio(path) || strings.HasPrefix(entry.Name(), "._") {
			return nil
		}
		result.Files++
		seen[path] = true
		if known[path] != "" || removed[path] {
			return nil
		}
		f := Found{Path: path}
		if info, err := entry.Info(); err == nil {
			f.Size, f.Modified = info.Size(), info.ModTime()
		}
		fresh = append(fresh, f)
		return nil
	})

	var gone []string
	for path := range known {
		if !seen[path] {
			gone = append(gone, path)
		}
	}
	// A move is a gone track and a new one with the same name and size.
	bySignature := map[string]string{}
	for _, path := range gone {
		if _, err := os.Lstat(path); err == nil {
			continue // skipped by the walk, not gone
		}
		var size int64
		s.Store.DB.QueryRow(`SELECT COALESCE(size, 0) FROM item WHERE id = ?`, known[path]).Scan(&size)
		bySignature[filepath.Base(path)+"|"+strconv.FormatInt(size, 10)] = path
	}
	for _, f := range fresh {
		if old, ok := bySignature[filepath.Base(f.Path)+"|"+strconv.FormatInt(f.Size, 10)]; ok {
			delete(bySignature, filepath.Base(f.Path)+"|"+strconv.FormatInt(f.Size, 10))
			if s.moveTrack(libraryID, known[old], f) == nil {
				result.Moved++
				continue
			}
		}
		if err := s.insertTrack(libraryID, f); err != nil {
			s.Log.Info("music: could not add", "file", f.Path, "error", err)
			continue
		}
		result.Added++
	}
	// An unplugged drive or a half-mounted share looks like everything went.
	// More than a third gone is that, not a clear-out — moves above still
	// count, since the files they found are plainly there.
	if len(known) >= 30 && len(bySignature)*3 > len(known) {
		s.Log.Info("music: too much missing to believe; nothing removed",
			"library", libraryID, "missing", len(bySignature), "known", len(known))
		bySignature = nil
	}
	for _, path := range bySignature {
		if _, err := s.Store.Remove(known[path]); err == nil {
			result.Removed++
		}
	}
	if result.Removed+result.Moved > 0 {
		dropEmptyAlbums(s.Store.DB, libraryID)
	}
	return result, nil
}

// insertTrack files one new track under its album, making the album and its
// artists where the library has none by those names.
func (s *Scanner) insertTrack(libraryID string, f Found) error {
	tags := s.musicTags(f.Path)
	albumID, err := ensureAlbum(s.Store.DB, libraryID, filepath.Dir(f.Path), tags, addedAt(f))
	if err != nil {
		return err
	}
	for _, name := range append(splitArtists(tags.Artist), tags.AlbumArtist) {
		ensureArtist(s.Store.DB, name)
	}
	_, err = s.Store.DB.Exec(`
		INSERT INTO item (id, type, name, sort_name, library_id, parent_id, album, album_artist,
			artists, index_number, parent_index_number, production_year, runtime_ticks,
			container, path, size, total_bitrate, is_folder, date_created)
		VALUES (?, 'Audio', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
		ON CONFLICT DO NOTHING`,
		ItemID(f.Path), tags.Title, tags.Title, libraryID, albumID,
		nullString(tags.Album), nullString(tags.AlbumArtist), nullString(tags.Artist),
		nullInt(int64(tags.Track)), nullInt(int64(tags.Disc)), nullInt(int64(tags.Year)),
		nullInt(tags.Ticks), nullString(tags.Container), f.Path, f.Size, nullInt(tags.Bitrate),
		addedAt(f))
	return err
}

// moveTrack points a track at where it went, under the album of its new
// folder. Its id, play count and favourite go with it.
func (s *Scanner) moveTrack(libraryID, id string, f Found) error {
	tags := s.musicTags(f.Path)
	albumID, err := ensureAlbum(s.Store.DB, libraryID, filepath.Dir(f.Path), tags, addedAt(f))
	if err != nil {
		return err
	}
	_, err = s.Store.DB.Exec(`UPDATE item SET path = ?, parent_id = ? WHERE id = ?`, f.Path, albumID, id)
	return err
}

// ensureAlbum finds the album a track belongs to — by its tags' album and
// album artist, then by its folder — or makes one.
func ensureAlbum(db *sql.DB, libraryID, folder string, t MusicTags, added string) (string, error) {
	var id string
	if t.Album != "" {
		db.QueryRow(`SELECT id FROM item WHERE type = 'MusicAlbum' AND library_id = ? AND name = ?
			AND COALESCE(album_artist, '') = ? LIMIT 1`, libraryID, t.Album, t.AlbumArtist).Scan(&id)
	}
	if id == "" {
		db.QueryRow(`SELECT id FROM item WHERE type = 'MusicAlbum' AND library_id = ? AND path = ? LIMIT 1`,
			libraryID, folder).Scan(&id)
	}
	if id != "" {
		return id, nil
	}
	name := t.Album
	if name == "" {
		name = filepath.Base(folder)
	}
	id = ItemID("album:" + libraryID + ":" + folder + ":" + name)
	_, err := db.Exec(`INSERT INTO item (id, type, name, sort_name, library_id, parent_id, path,
			album_artist, artists, production_year, is_folder, date_created)
		VALUES (?, 'MusicAlbum', ?, ?, ?, ?, ?, ?, ?, ?, 1, ?) ON CONFLICT DO NOTHING`,
		id, name, name, libraryID, libraryID, folder, nullString(t.AlbumArtist),
		nullString(t.AlbumArtist), nullInt(int64(t.Year)), added)
	return id, err
}

// ensureArtist makes an artist row for a name the library has never seen.
func ensureArtist(db *sql.DB, name string) {
	if name = strings.TrimSpace(name); name == "" {
		return
	}
	db.Exec(`INSERT INTO item (id, type, name, sort_name, is_folder, date_created)
		SELECT ?, 'MusicArtist', ?, ?, 1, ? WHERE NOT EXISTS
		(SELECT 1 FROM item WHERE type = 'MusicArtist' AND name = ?)`,
		ItemID("artist:"+name), name, name, time.Now().UTC().Format(time.RFC3339), name)
}

// dropEmptyAlbums removes albums this library has left with no tracks.
func dropEmptyAlbums(db *sql.DB, libraryID string) {
	db.Exec(`DELETE FROM item WHERE type = 'MusicAlbum' AND library_id = ?
		AND NOT EXISTS (SELECT 1 FROM item t WHERE t.parent_id = item.id)`, libraryID)
}

// splitArtists reads an artist tag the ways taggers write several: "A; B",
// "A / B", or Jellyfin's own "A|B".
func splitArtists(tag string) []string {
	f := func(r rune) bool { return r == ';' || r == '|' || r == '/' }
	var out []string
	for _, part := range strings.FieldsFunc(tag, f) {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

// musicTags probes one file; a file ffprobe cannot read is still filed, by
// its name and folder.
func (s *Scanner) musicTags(path string) MusicTags {
	var raw []byte
	if s.FFprobe != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		raw, _ = exec.CommandContext(ctx, s.FFprobe, "-v", "quiet", "-print_format", "json",
			"-show_format", path).Output()
	}
	return ParseMusicTags(raw, path)
}

// isMusicLibrary says whether a library holds music: declared so, or already
// holding tracks the import brought in.
func isMusicLibrary(db *store.Store, libraryID string) bool {
	var n int
	db.DB.QueryRow(`SELECT
		EXISTS (SELECT 1 FROM library_folder lf JOIN item v ON v.id = lf.view_id
		        WHERE lf.folder_id = ? AND v.collection_type = 'music')
		OR EXISTS (SELECT 1 FROM item WHERE library_id = ? AND type = 'Audio')`,
		libraryID, libraryID).Scan(&n)
	return n == 1
}
