package scanner

import (
	"log/slog"
	"os"
	"sort"
	"strings"

	"lumiere-server/internal/store"
)

// AdoptOrphanFiles deals with files that belong to no library.
//
// The Jellyfin import left 841 rows with no library_id — extras, mostly, and
// files it knew at paths since renamed. The scanner checks a library's own
// rows against the disk, so these were never checked: 197 pointed at files
// long gone and sat on as blank, pictureless titles, and every re-import
// brought them back.
//
// A file still on disk joins the library whose folder holds it, and is
// watched from then on like any other. A file that is gone, with its
// library's drive plainly mounted, goes to Removed Items — restorable,
// never deleted outright.
func AdoptOrphanFiles(db *store.Store, roots []Root, log *slog.Logger) (adopted, removed int) {
	sorted := append([]Root(nil), roots...)
	// Longest first, so a nested library wins over the folder around it.
	sort.Slice(sorted, func(i, j int) bool { return len(sorted[i].Path) > len(sorted[j].Path) })
	mounted := map[string]bool{}
	for _, r := range sorted {
		if info, err := os.Stat(r.Path); err == nil && info.IsDir() {
			mounted[r.Path] = true
		}
	}

	rows, err := db.DB.Query(`SELECT id, path FROM item
		WHERE library_id IS NULL AND is_folder = 0 AND path IS NOT NULL AND path <> ''
		  AND path NOT LIKE '\%%' ESCAPE '\' AND type <> 'MusicArtist'`)
	if err != nil {
		log.Error("orphans: could not list", "error", err)
		return 0, 0
	}
	type orphan struct{ id, path string }
	var found []orphan
	for rows.Next() {
		var o orphan
		if rows.Scan(&o.id, &o.path) == nil {
			found = append(found, o)
		}
	}
	rows.Close()

	for _, o := range found {
		var root *Root
		for i := range sorted {
			if strings.HasPrefix(o.path, strings.TrimSuffix(sorted[i].Path, "/")+"/") {
				root = &sorted[i]
				break
			}
		}
		if root == nil || !mounted[root.Path] {
			continue
		}
		if _, err := os.Stat(o.path); err == nil {
			if _, err := db.DB.Exec(`UPDATE item SET library_id = ? WHERE id = ?`, root.LibraryID, o.id); err == nil {
				adopted++
			}
			continue
		}
		if _, err := db.Remove(o.id); err == nil {
			removed++
		}
	}
	if adopted+removed > 0 {
		log.Info("scan: files with no library settled", "joined", adopted, "gone, to Removed Items", removed)
	}
	return adopted, removed
}
