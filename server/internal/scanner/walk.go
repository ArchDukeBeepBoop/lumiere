package scanner

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Found is one media file on disk.
type Found struct {
	Path string
	Size int64
	// Modified is the file's own timestamp, which is what "recently added"
	// should mean. Stamping the scan's own clock instead put 1,052 files —
	// mostly decade-old creditless openings Jellyfin had never catalogued — at
	// the top of every Latest shelf, burying the shows actually added that week.
	Modified time.Time
	Layout   Layout
}

// skipDirs are the directories a media tree carries that hold no media.
//
// `.` prefixed anything, plus the two every scanner trips over: Jellyfin's own
// metadata tree and the Trash a network volume keeps.
func skipDir(name string) bool {
	if strings.HasPrefix(name, ".") {
		return true
	}
	switch strings.ToLower(name) {
	case "metadata", "$recycle.bin", "#recycle", "lost+found":
		return true
	}
	return false
}

// Walk finds every media file under a library root.
//
// `onFound` is called as each file is discovered rather than after the whole
// tree is read. On a 20TB volume the walk alone is minutes, and a scan that
// reports nothing until a library finishes is indistinguishable from one that
// has hung — which is exactly how the first run of this looked.
//
// Errors on individual entries are skipped rather than returned: one unreadable
// folder on a network share must not abandon the other thirty thousand files,
// and a scan that fails halfway is worse than one that reports what it found.
// The root failing to open at all *is* returned — that is a mount that is not
// there, and continuing would look like an empty library.
func Walk(root string, onFound func(Found)) error {
	if info, err := os.Stat(root); err != nil || !info.IsDir() {
		if err == nil {
			err = fs.ErrInvalid
		}
		return err
	}

	_ = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			// Unreadable: skip the branch, keep the walk.
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
		if !IsMedia(path) {
			return nil
		}
		var size int64
		var modified time.Time
		if info, err := entry.Info(); err == nil {
			size = info.Size()
			modified = info.ModTime()
		}
		// A file too small to be video is a sample, a placeholder, or a
		// download that never finished. Cataloguing it gives the library an
		// entry that fails to play with no explanation.
		if size > 0 && size < minimumMediaBytes {
			return nil
		}
		onFound(Found{
			Path: path, Size: size, Modified: modified,
			Layout: Describe(root, path),
		})
		return nil
	})
	return nil
}

// minimumMediaBytes is the floor for a real file. One megabyte: shorter than any
// episode and larger than every stub.
const minimumMediaBytes int64 = 1 << 20
