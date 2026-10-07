// Package scanner builds the library from the filesystem, without Jellyfin.
//
// The import in `internal/importer` reads Jellyfin's database, which makes this
// server a mirror: nothing can appear here that Jellyfin has not catalogued
// first, and a file copied in five minutes ago is invisible for as long as
// Jellyfin takes to notice it. This package removes that dependency for the part
// that matters most — what exists — by walking the media roots directly.
//
// Deliberately additive in this pass. A scanner that deletes is a scanner that
// can empty a library on a mount that failed to come up, and the recovery is a
// re-import of watch state that no longer has rows to attach to. Missing files
// are reported, not removed.
package scanner

import (
	"crypto/sha256"
	"encoding/hex"
	"path/filepath"
	"strings"
)

// MediaExtensions are the containers this server will serve.
//
// A list rather than "anything with a video stream", because the alternative is
// probing every file in a media tree to find out it is a `.nfo`. These are what
// the library actually holds; anything else is not media this app can play.
var MediaExtensions = map[string]bool{
	".mkv": true, ".mp4": true, ".m4v": true, ".avi": true, ".mov": true,
	".wmv": true, ".ts": true, ".m2ts": true, ".webm": true, ".flv": true,
	".mpg": true, ".mpeg": true, ".ogv": true, ".rmvb": true, ".divx": true,
}

// IsMedia reports whether a path is a file this server would serve.
//
// Hidden files and macOS resource forks are excluded by name: a media tree on a
// Mac is full of `._Show.mkv` files that are four kilobytes of metadata and
// would otherwise be catalogued as episodes.
func IsMedia(path string) bool {
	name := filepath.Base(path)
	if strings.HasPrefix(name, ".") {
		return false
	}
	return MediaExtensions[strings.ToLower(filepath.Ext(name))]
}

// ItemID is the id a scanned file gets.
//
// Derived from the path so it is stable: the same file scanned twice is the same
// item, without a lookup table, and a scan that runs while the previous one is
// still being read cannot produce a second copy of anything.
//
// Jellyfin's ids are its own GUIDs, and these are hashes of paths — they share
// a namespace but cannot collide in practice, and a file that Jellyfin *also*
// knows about is matched by path before an id is ever generated. See
// `Reconcile`.
func ItemID(path string) string {
	sum := sha256.Sum256([]byte(path))
	return hex.EncodeToString(sum[:16])
}
