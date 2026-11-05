package media

import (
	"database/sql"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"time"
)

// Old artwork, cleared when newer replaced it.
//
// A title keeps one poster and one backdrop, but each source writes its own
// file — a frame grab, an identify, AniList, a mosaic — so choosing a new
// picture left the old file behind with nothing pointing at it: 1,678 files
// on the first count. This removes any original that no image row names, a
// day after it was last written, so a picture being saved is never caught
// between its file and its row.
//
// The resized copies (two-letter folders, see ImageCache) are left alone:
// they are a bounded cache with their own pruning. And a sweep that would
// remove more than a fifth of the originals stops before removing anything —
// a database and a folder that disagree that much are a mistake to look at,
// not artwork to delete.

// SweepOrphanArt removes unreferenced originals under root; returns files
// and bytes removed.
func SweepOrphanArt(db *sql.DB, root string, log *slog.Logger) (int, int64) {
	if info, err := os.Stat(root); err != nil || !info.IsDir() {
		return 0, 0
	}
	referenced := map[string]bool{}
	rows, err := db.Query(`SELECT DISTINCT path FROM image`)
	if err != nil {
		return 0, 0
	}
	for rows.Next() {
		var p string
		if rows.Scan(&p) == nil {
			referenced[filepath.Clean(p)] = true
		}
	}
	rows.Close()
	if len(referenced) == 0 {
		return 0, 0
	}
	cutoff := time.Now().Add(-24 * time.Hour)
	var originals int
	var orphans []string
	var sizes []int64
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		if d.IsDir() {
			// The resized-copy cache: images/ab/cd/...
			if path != root && filepath.Dir(rel) == "." && len(d.Name()) == 2 {
				return fs.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() || d.Name() == ".DS_Store" {
			return nil
		}
		originals++
		if referenced[filepath.Clean(path)] {
			return nil
		}
		if info, err := d.Info(); err == nil && info.ModTime().Before(cutoff) {
			orphans = append(orphans, path)
			sizes = append(sizes, info.Size())
		}
		return nil
	})
	if len(orphans) == 0 {
		return 0, 0
	}
	if len(orphans)*5 > originals {
		log.Warn("old artwork: too much unreferenced to be real; nothing removed", "unreferenced", len(orphans), "of", originals)
		return 0, 0
	}
	var removed int
	var freed int64
	for i, p := range orphans {
		if os.Remove(p) == nil {
			removed++
			freed += sizes[i]
		}
	}
	log.Info("old artwork removed", "files", removed, "megabytes", freed>>20)
	return removed, freed
}
