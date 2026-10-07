package media

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"sync/atomic"
)

// The cache is bounded, because nothing else bounds it.
//
// A variant averages 40 KB and the library holds 105,826 images at up to seven
// widths. Browsing everything once would put roughly 1.9 GB here at a single
// width alone — on a machine whose whole point is that the 23 GB of artwork is
// not duplicated. So: a cap, and eviction of whatever was used longest ago.
//
// Everything here is disposable by construction. Losing a variant costs one
// re-resize, never an image, so eviction can be as blunt as it likes.
const defaultMaxBytes = 512 << 20 // 512 MB, half the acceptance budget for all of data/

type pruner struct {
	pending atomic.Int64 // bytes written since the last sweep
}

// maybePrune sweeps once enough new bytes have accumulated to matter.
//
// Counted in bytes rather than in writes, which was the first version and was
// wrong: most requests never write anything — an image already cached, one
// small enough to need no resize, one whose original is smaller than the
// re-encode — so a counter of "writes" advanced unpredictably and a cache
// measured at 25 MB sat happily over an 8 MB cap. Bytes are what the cap is
// about, so bytes are what triggers the check, and the overshoot is bounded at
// a tenth of the cap however many files that turns out to be.
func (c *ImageCache) maybePrune(written int) {
	max := c.MaxBytes
	if max <= 0 {
		max = defaultMaxBytes
	}
	if c.prune.pending.Add(int64(written)) < max/10 {
		return
	}
	c.prune.pending.Store(0)
	_ = pruneDir(c.Dir, max)
}

// Prune sweeps unconditionally. Called once at startup so a cache left
// oversized by a previous run — or by the cap being lowered — is corrected
// without waiting for enough traffic to trigger it.
func (c *ImageCache) Prune() error {
	max := c.MaxBytes
	if max <= 0 {
		max = defaultMaxBytes
	}
	return pruneDir(c.Dir, max)
}

type cached struct {
	path string
	size int64
	used int64 // modification time; see below
}

// pruneDir deletes least-recently-used variants until the tree fits in max.
//
// Ordered by modification time rather than access time: atime is unreliable
// (mounts disable it, and reading a file to serve it would rewrite it), while
// mtime is when the variant was rendered. That makes this least-recently-
// *created* rather than least-recently-used, which is the wrong order in
// theory. In practice a variant is rendered when it is first shown, so the
// oldest ones are the ones browsed longest ago — and being wrong costs a
// re-resize.
func pruneDir(dir string, max int64) error {
	var files []cached
	var total int64
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		// Only the resized variants, which live in two-letter shard folders.
		// The same tree holds originals — frames taken here, artwork fetched,
		// posters made for collections — and treating those as disposable
		// deleted 328 of them, oldest first, whenever the tree passed the cap:
		// tiles Home still drew from the app's cache and a See All page drew
		// blank.
		if d.IsDir() {
			if path != dir && !isShard(d.Name()) {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Dir(path) == dir {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		files = append(files, cached{path: path, size: info.Size(), used: info.ModTime().UnixNano()})
		total += info.Size()
		return nil
	})
	if err != nil || total <= max {
		return err
	}

	sort.Slice(files, func(i, j int) bool { return files[i].used < files[j].used })
	// Down to 80% rather than exactly to the cap, so the next few writes do not
	// each trigger another sweep.
	target := max * 8 / 10
	for _, f := range files {
		if total <= target {
			break
		}
		if os.Remove(f.path) == nil {
			total -= f.size
		}
	}
	return nil
}

// isShard is a variant folder's name: two hex digits.
func isShard(name string) bool {
	if len(name) != 2 {
		return false
	}
	for _, r := range name {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') {
			return false
		}
	}
	return true
}
