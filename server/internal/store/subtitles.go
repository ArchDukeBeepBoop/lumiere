package store

import (
	"database/sql"
	"fmt"
	"path/filepath"
	"strings"
)

// External subtitles the server fetched itself.
//
// The scanner does not write stream rows — those came from the Jellyfin
// import, which read ffprobe's answer for every file it knew. A subtitle
// downloaded now has to announce itself, and it announces itself the same
// way an imported sidecar does: a Subtitle row with is_external set and a
// path, which is what the streaming route already serves and what mpv is
// already told to load.

// AddExternalSubtitle records a downloaded subtitle file against an item and
// returns the stream index it was given.
//
// The index is one past the highest the item has. Jellyfin's indices are
// absolute across every stream of a file, and a client asks for a subtitle
// by that number, so the only rule that matters is that it is free and
// stable once written.
func (s *Store) AddExternalSubtitle(itemID, path, language, title string) (int, error) {
	var highest sql.NullInt64
	if err := s.DB.QueryRow(
		`SELECT max(idx) FROM stream WHERE item_id = ?`, itemID,
	).Scan(&highest); err != nil {
		return 0, err
	}
	index := int(highest.Int64) + 1
	if !highest.Valid {
		// A file the import never saw has no streams at all. Index 0 would
		// collide with the video stream a later probe writes, so downloaded
		// subtitles start high enough to stay out of the way.
		index = 100
	}
	codec := strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
	if codec == "srt" {
		codec = "subrip"
	}
	_, err := s.DB.Exec(`
		INSERT INTO stream (item_id, idx, type, codec, language, title,
		                    display_title, is_default, is_forced, is_external, path)
		VALUES (?, ?, 'Subtitle', ?, ?, ?, ?, 0, 0, 1, ?)
		ON CONFLICT(item_id, idx) DO UPDATE SET
		    codec = excluded.codec, language = excluded.language,
		    title = excluded.title, display_title = excluded.display_title,
		    path = excluded.path`,
		itemID, index, codec, nullable(language), nullable(title),
		nullable(displayTitle(language, title)), path)
	if err != nil {
		return 0, err
	}
	return index, nil
}

// ExternalSubtitlePath is where a downloaded subtitle for an item goes: beside
// the video, named after it, with the language in the name so several can sit
// together and so a later scan reads them the way it reads any sidecar.
func ExternalSubtitlePath(videoPath, language, extension string) string {
	base := strings.TrimSuffix(videoPath, filepath.Ext(videoPath))
	if language == "" {
		language = "und"
	}
	if extension == "" {
		extension = "srt"
	}
	return fmt.Sprintf("%s.%s.%s", base, language, extension)
}

func displayTitle(language, title string) string {
	switch {
	case title != "" && language != "":
		return strings.ToUpper(language) + " · " + title
	case title != "":
		return title
	case language != "":
		return strings.ToUpper(language)
	}
	return "Subtitle"
}
