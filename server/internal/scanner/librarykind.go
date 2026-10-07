package scanner

import (
	"database/sql"
	"path/filepath"
	"strings"
)

// What a library declares itself to be, and what that makes of a folder.
//
// The layout rules see one file at a time and cannot know whether the folder
// around it is a title or a place. The library's declaration can: in a
// television library a folder is a show, in a plain one a folder is a folder,
// and only in a film library is a folder with one file a film.

// libraryKind is the collection type of the view over a folder, and whether
// there is a view at all.
func (s *Scanner) libraryKind(libraryID string) (string, bool) {
	var kind sql.NullString
	err := s.Store.DB.QueryRow(`
		SELECT v.collection_type FROM library_folder lf
		JOIN item v ON v.id = lf.view_id
		WHERE lf.folder_id = ? LIMIT 1`, libraryID).Scan(&kind)
	if err != nil {
		return "", false
	}
	return kind.String, true
}

// plainFolders is a library declared as nothing in particular — Jellyfin's
// "Home Videos and Photos", or a mixed folder with no type at all. Its
// folders are folders: a place, not a title.
func plainFolders(kind string) bool {
	switch kind {
	case "", "homevideos", "folders", "mixed":
		return true
	}
	return false
}

// plainFolderFile reads a file in a plain folder library as a loose video.
//
// The film rule saw `Live Clips/Garden/one clip.mkv` and made a film called
// Garden, in its own folder — so the folder vanished from the library's tree and
// the clip took its name. With two clips the sibling rule named them by file,
// but "Clips" got two films both called Clips before its second file arrived.
// In a library that declared itself neither films nor shows, a folder holds
// videos named by their filenames, whatever their number; the same rule
// televisionFolder applies from the other side.
func plainFolderFile(path string, layout Layout) Layout {
	if layout.Kind != KindMovie {
		return layout
	}
	title, year := CleanTitle(strings.TrimSuffix(filepath.Base(path), filepath.Ext(path)))
	return Layout{Kind: KindLoose, Title: title, Year: year}
}

// televisionFolder reads a folder in a television library as a show.
//
// In a library declared as shows, a folder is a show — whatever it holds. The
// layout rules could only see one file at a time, so a folder with a single
// unnumbered video read as "a film in its own folder", and a one-episode
// series was catalogued as a movie with no episode list and no still. The
// sibling rule fixed the two-file case and left the one-file case exactly as
// wrong. The library's own declaration is the evidence the file could never
// carry: nobody puts films in a folder they told the server holds shows.
func televisionFolder(root, path string, layout Layout) Layout {
	if layout.Kind != KindMovie {
		return layout
	}
	relative, err := filepath.Rel(root, path)
	if err != nil {
		return layout
	}
	parts := strings.Split(filepath.ToSlash(relative), "/")
	if len(parts) < 2 {
		return layout
	}
	base := strings.TrimSuffix(parts[len(parts)-1], filepath.Ext(path))
	series, year := CleanTitle(parts[0])
	return Layout{
		Kind: KindEpisode, Series: series, SeriesPath: filepath.Join(root, parts[0]),
		Season: 1, Episode: episodeFromName(base), Title: series, Year: year,
	}
}
