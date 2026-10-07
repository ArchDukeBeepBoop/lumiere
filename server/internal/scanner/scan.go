package scanner

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"lumiere-server/internal/store"
)

// Result is what one pass over one library did.
type Result struct {
	Library string
	Files   int
	Added   int
	Probed  int
	// Missing are catalogued files no longer on disk that this pass declined
	// to remove — see reconcile for the guard.
	Missing int
	// Moved are files found at a new path and matched to their old row.
	Moved int
	// Removed are files gone from disk whose rows were dropped.
	Removed int

	// added is every file this pass inserted, for the move matching.
	added []Found
}

// Scanner builds the library from the filesystem.
type Scanner struct {
	Store *store.Store
	Log   *slog.Logger
	// FFprobe is the tool's path, or empty to skip probing. Resolved once by
	// the caller so a missing tool is reported at startup rather than forty
	// thousand times during a scan.
	FFprobe string

	// pass is the state of a multi-library pass, for moves across libraries.
	// Nil outside one: a single ScanLibrary settles its own missing files.
	// See BeginPass.
	pass *passState
}

// ScanLibrary walks one library root, adds what the database does not have,
// and settles what it no longer finds.
//
// The settling is guarded rather than absent — see reconcile. It used to be
// absent on the reasoning that a drive which failed to come up looks like a
// library whose files were all deleted; that is still true, and it is why a
// pass will not remove more than a third of a library. But a scan that could
// never remove anything left every moved file listed twice, once with its
// picture and once without.
func (s *Scanner) ScanLibrary(libraryID, root string, onProgress func(Result)) (Result, error) {
	result := Result{Library: filepath.Base(root)}
	// What kind of library this is decides what a folder means. See
	// televisionFolders.
	kind, declared := s.libraryKind(libraryID)
	isTV := kind == "tvshows"
	// Only a library that has a view at all. One without — a bare root, as
	// the tests build — is not declared as anything, and the film rule
	// stands.
	isFolders := declared && plainFolders(kind)

	// Read before the walk. Every file is checked against this, and asking the
	// database per file would be one query per item across forty thousand of
	// them — on a first run that is the whole cost of the scan.
	known, err := s.knownPaths(libraryID)
	if err != nil {
		return result, err
	}
	seen := make(map[string]bool, len(known))
	sizes, _ := s.knownSizes(libraryID)
	var changed []Found

	err = Walk(root, func(file Found) {
		result.Files++
		seen[file.Path] = true
		if !known[file.Path] {
			if isTV {
				file.Layout = televisionFolder(root, file.Path, file.Layout)
			}
			if isFolders {
				file.Layout = plainFolderFile(file.Path, file.Layout)
			}
			if err := s.insert(libraryID, root, file, &result); err != nil {
				// One file that will not insert is not a scan that should stop.
				s.Log.Info("scan: could not add", "path", file.Path, "error", err)
			}
		} else if size, ok := sizes[file.Path]; ok && size != file.Size && file.Size > 0 {
			changed = append(changed, file) // replaced in place; see refresh.go
		}
		if onProgress != nil && result.Files%25 == 0 {
			// Every twenty-five files. Often enough that the count visibly
			// moves, rare enough that a mutex is not taken forty thousand times
			// for a number nobody reads that fast.
			onProgress(result)
		}
	})
	if err != nil {
		return result, fmt.Errorf("walk %s: %w", root, err)
	}
	s.rereadChanged(changed)

	// Remembered across the pass before this library settles its own
	// missing files, so a library read later can pair a loss against them.
	if s.pass != nil {
		for _, file := range result.added {
			s.pass.added[moveKey{filepath.Base(file.Path), file.Size}] = file
		}
	}
	if err := s.reconcile(libraryID, known, seen, &result); err != nil {
		s.Log.Info("scan: reconcile failed", "library", libraryID, "error", err)
	}
	return result, nil
}

// knownPaths is every media file this library already holds.
//
// By path rather than by id, and that is what makes the scanner safe to run
// beside the Jellyfin import: a file both of them know about is matched here and
// never inserted twice, whatever id Jellyfin gave it.
//
// Filtered to files this scanner would actually find, which is what makes the
// missing count mean anything. Unfiltered it reported 8,103 missing files on a
// first run: series and season rows carry the path of their *folder*, a walk
// never yields a folder, and every one of them looked deleted. Music was the
// same in reverse — 3,828 tracks this scanner does not handle at all, counted as
// gone.
func (s *Scanner) knownPaths(libraryID string) (map[string]bool, error) {
	// Removed rows count as known: a file taken out of the library and left
	// on disk must not come straight back at the next scan.
	rows, err := s.Store.DB.Query(`
		SELECT path FROM item WHERE library_id = ? AND path IS NOT NULL
		UNION
		SELECT json_extract(row, '$.path') FROM removed_item
		WHERE json_extract(row, '$.library_id') = ? AND json_extract(row, '$.path') IS NOT NULL`,
		libraryID, libraryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	known := map[string]bool{}
	for rows.Next() {
		var path string
		if err := rows.Scan(&path); err != nil {
			return nil, err
		}
		if IsMedia(path) {
			known[path] = true
		}
	}
	return known, rows.Err()
}

// insert writes one newly found file, and the series and season it needs.
func (s *Scanner) insert(libraryID, root string, file Found, result *Result) error {
	tx, err := s.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var probe Probe
	if s.FFprobe != "" {
		if p, err := ProbeFile(s.FFprobe, file.Path); err == nil {
			probe = p
			result.Probed++
		}
	}

	extraType := ExtraType(root, file.Path)
	itemType, parentID, seriesID := "Video", "", ""
	// A "film in its own folder" that shares the folder with other films is
	// not in its own folder: `Movies/DC/Superman (1978).mkv` beside forty
	// others is a genre folder, and each file is a film named by its
	// filename, filed under the folder. The layout is per file and cannot
	// see this; the directory can.
	ownFolder := 1
	if file.Layout.Kind == KindMovie && mediaSiblings(file.Path) > 1 {
		title, year := CleanTitle(strings.TrimSuffix(filepath.Base(file.Path), filepath.Ext(file.Path)))
		file.Layout.Title, file.Layout.Year = title, year
		ownFolder = 0
	}
	switch file.Layout.Kind {
	case KindMovie:
		itemType = "Movie"
		// Under the folders above its own. See ensureFolders.
		parentID, err = ensureFolders(tx, libraryID, root, file.Path, ownFolder)
		if err != nil {
			return err
		}
	case KindLoose:
		parentID, err = ensureFolders(tx, libraryID, root, file.Path, 0)
		if err != nil {
			return err
		}
	case KindEpisode:
		itemType = "Episode"
		seriesID, err = ensureSeries(tx, libraryID, file.Layout)
		if err != nil {
			return err
		}
		parentID, err = ensureSeason(tx, libraryID, seriesID, file.Layout)
		if err != nil {
			return err
		}
	}

	id := ItemID(file.Path)
	name := displayName(file)
	var ticks any
	if probe.DurationSeconds > 0 {
		ticks = int64(probe.DurationSeconds * 10_000_000)
	}
	var season, episode any
	if file.Layout.Kind == KindEpisode {
		if file.Layout.Season >= 0 {
			season = file.Layout.Season
		}
		if file.Layout.Episode > 0 {
			episode = file.Layout.Episode
		}
	}

	res, err := tx.Exec(`
		INSERT INTO item (
			id, type, name, sort_name, library_id, parent_id, series_id,
			parent_index_number, index_number, path, size, runtime_ticks,
			container, total_bitrate, production_year, extra_type, is_folder, date_created
		) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?)
		ON CONFLICT DO NOTHING`,
		id, itemType, name, name, libraryID,
		nullString(parentID), nullString(seriesID),
		season, episode, file.Path, file.Size, ticks,
		nullString(probe.Container), nullInt(probe.Bitrate),
		nullInt64(int64(file.Layout.Year)),
		nullString(extraType),
		addedAt(file),
	)
	if err != nil {
		return err
	}
	// Nothing written means the file already has a row — by id, or by path
	// under another id — and one file is one item. Not an addition.
	if n, _ := res.RowsAffected(); n == 0 {
		return tx.Commit()
	}
	result.Added++
	result.added = append(result.added, file)
	return tx.Commit()
}

// isTelevision says whether a library was declared as shows.
// mediaSiblings counts the media files in a file's directory, itself included.
func mediaSiblings(path string) int {
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		return 1
	}
	count := 0
	for _, entry := range entries {
		if !entry.IsDir() && IsMedia(entry.Name()) {
			count++
		}
	}
	return count
}
