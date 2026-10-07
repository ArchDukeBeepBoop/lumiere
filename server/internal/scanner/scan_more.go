package scanner

import (
	"os"
	"path/filepath"
	"time"
)

// Split from scan.go for the 300-line rule.

// displayName is what the item is called before anything has scraped it.
//
// The filename for an episode, because that is what distinguishes one from
// another before numbering is known; the cleaned title for anything else.
func displayName(file Found) string {
	base := filepath.Base(file.Path)
	name := base[:len(base)-len(filepath.Ext(base))]
	if file.Layout.Kind == KindMovie && file.Layout.Title != "" {
		return file.Layout.Title
	}
	cleaned, _ := CleanTitle(name)
	if cleaned == "" {
		return name
	}
	return cleaned
}

// addedAt is when this file should count as having arrived.
//
// The file's own timestamp, not the scan's. A scanner that stamps `now` says
// every file it has just noticed is new — which is false for the ten-year-old
// extras that were simply never catalogued, and it is exactly what pushed a
// week's real additions off the front of every Latest shelf.
//
// The scan's clock is the fallback, for a filesystem that reports no time at
// all. Rare, and better than a null nothing can sort by.
func addedAt(file Found) string {
	if file.Modified.IsZero() {
		return time.Now().UTC().Format(time.RFC3339)
	}
	return file.Modified.UTC().Format(time.RFC3339)
}

// folderDate is when a container should count as having arrived.
//
// The directory's own timestamp. The scan's clock is only used where there is
// no directory to ask — see `addedAt`, which makes the same trade for files and
// for the same reason.
func folderDate(path string) string {
	if path != "" {
		if info, err := os.Stat(path); err == nil {
			return info.ModTime().UTC().Format(time.RFC3339)
		}
	}
	return time.Now().UTC().Format(time.RFC3339)
}
