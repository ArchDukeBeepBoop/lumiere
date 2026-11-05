package scanner

import (
	"log/slog"
	"os"
	"strings"

	"lumiere-server/internal/store"
)

// A file's real container, not its name's.
//
// The apps send an MP4 to AVFoundation and everything else to mpv, so the
// container the server reports decides which player opens a file. The
// Jellyfin import recorded it from the file's extension, and 161 files named
// .mp4 were not MP4s: 158 MPEG transport streams and 3 Matroska files. Each
// went to AVFoundation, which cannot open either, and failed — while the same
// file opened from the Finder, by mpv, played.

// NormalizeContainer turns ffprobe's format name into the short one the apps
// match on: "mov,mp4,m4a,3gp,3g2,mj2" is mp4, "matroska,webm" mkv, and a
// transport stream stays "mpegts", which no app sends to AVFoundation.
func NormalizeContainer(format string) string {
	f := strings.ToLower(strings.TrimSpace(format))
	switch {
	case f == "":
		return ""
	case strings.Contains(f, "mp4") || strings.HasPrefix(f, "mov"):
		return "mp4"
	case strings.Contains(f, "matroska"):
		return "mkv"
	}
	if i := strings.Index(f, ","); i > 0 {
		return f[:i]
	}
	return f
}

const metaContainersChecked = "containers_checked_v1"

// RecheckContainers probes, once, every file recorded as an MP4 or a
// QuickTime file, and records what it really is where that differs. In the
// background; a run with the media drive unplugged is not counted as done.
func RecheckContainers(db *store.Store, log *slog.Logger) {
	if done, _ := db.Meta(metaContainersChecked); done != "" {
		return
	}
	tool := FindFFprobe()
	if tool == "" {
		return
	}
	rows, err := db.DB.Query(`SELECT id, path, container FROM item
		WHERE type IN ('Movie', 'Episode', 'Video') AND container IN ('mp4', 'm4v', 'mov', 'qt')
		  AND path IS NOT NULL AND path <> ''`)
	if err != nil {
		return
	}
	type file struct{ id, path, container string }
	var files []file
	for rows.Next() {
		var f file
		rows.Scan(&f.id, &f.path, &f.container)
		files = append(files, f)
	}
	rows.Close()
	var fixed, unreadable int
	for _, f := range files {
		if _, err := os.Stat(f.path); err != nil {
			unreadable++
			continue
		}
		probe, err := ProbeFile(tool, f.path)
		real := NormalizeContainer(probe.Container)
		if err != nil || real == "" {
			unreadable++
			continue
		}
		if real != "mp4" && real != f.container {
			if _, err := db.DB.Exec(`UPDATE item SET container = ? WHERE id = ?`, real, f.id); err == nil {
				fixed++
				log.Info("container: not what its name says", "file", f.path, "was", f.container, "is", real)
			}
		}
	}
	if unreadable*10 > len(files) {
		log.Warn("container check: too many files unreadable (is a drive unplugged?); it runs again next start",
			"unreadable", unreadable, "of", len(files))
		return
	}
	db.SetMeta(metaContainersChecked, "1")
	log.Info("container check complete", "checked", len(files), "fixed", fixed)
}
