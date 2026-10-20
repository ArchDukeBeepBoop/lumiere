// Package safefs writes files only where they belong.
//
// Every file this server writes from a request — a fetched subtitle, chosen
// artwork, lyrics — has its path built from something the request named. A
// language of "../../Library/LaunchAgents/x" once reached a path unchecked:
// the same class of hole as Jellyfin's CVE-2026-35031. So a write names the
// folder it must land in, and is refused if the cleaned path, or the real
// folder behind any symlink, is anywhere else.
package safefs

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// ErrOutside is a path that would land outside its folder.
var ErrOutside = errors.New("refused: path leaves its folder")

// Inside reports whether path, cleaned and with symlinks in its folder
// resolved, is inside root.
func Inside(root, path string) bool {
	root, err := filepath.Abs(filepath.Clean(root))
	if err != nil {
		return false
	}
	path, err = filepath.Abs(filepath.Clean(path))
	if err != nil {
		return false
	}
	if realRoot, err := filepath.EvalSymlinks(root); err == nil {
		root = realRoot
	}
	dir := filepath.Dir(path)
	if realDir, err := filepath.EvalSymlinks(dir); err == nil {
		path = filepath.Join(realDir, filepath.Base(path))
	}
	return path != root && strings.HasPrefix(path, root+string(filepath.Separator))
}

// WriteFile writes data to path only if path is inside root, and never
// through a symlink at the final name.
func WriteFile(root, path string, data []byte, perm os.FileMode) error {
	if !Inside(root, path) {
		return ErrOutside
	}
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return ErrOutside
	}
	return os.WriteFile(path, data, perm)
}

// Token keeps only letters, digits, '-' and '_', at most max of them: what a
// language code or a file extension may be, and nothing a path can use.
func Token(s string, max int) string {
	var b strings.Builder
	for _, r := range s {
		if b.Len() >= max {
			break
		}
		if r == '-' || r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
}
