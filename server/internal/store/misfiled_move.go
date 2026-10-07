package store

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Where a misfiled episode belongs, and moving it there.
//
// The show folder holding the season folders is looked through for the one
// that names the file's own season — "Season 1", "S01", "Season 01 - Arc" —
// and a plain "Season N" is made beside the others when there is none. The
// file moves with every sidecar that shares its name (subtitles, .nfo), on
// the same drive, so it is a rename and never a copy. The scanner already
// follows a moved file, so the item keeps its history.

// SeasonFolderFor is the folder a file named for `season` belongs in: an
// existing sibling season folder, or a new "Season N" beside them. Pure
// apart from reading the show folder's listing.
func SeasonFolderFor(path string, season int) (string, error) {
	show := filepath.Dir(filepath.Dir(path))
	entries, err := os.ReadDir(show)
	if err != nil {
		return "", err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if n, ok := FolderSeason(filepath.Join(show, e.Name(), "x")); ok && n == season {
			return filepath.Join(show, e.Name()), nil
		}
	}
	return filepath.Join(show, fmt.Sprintf("Season %d", season)), nil
}

// Move is one file moved, for Undo.
type Move struct{ From, To string }

// MoveWithSidecars moves a video and every file beside it sharing its base
// name into `folder`, refusing to overwrite anything already there.
func MoveWithSidecars(path, folder string) ([]Move, error) {
	if err := os.MkdirAll(folder, 0o755); err != nil {
		return nil, err
	}
	base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	dir := filepath.Dir(path)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var moves []Move
	for _, e := range entries {
		// The name exactly, then a dot: S01E20's sidecars, never S01E200.
		if e.IsDir() || !strings.HasPrefix(e.Name(), base+".") {
			continue
		}
		from := filepath.Join(dir, e.Name())
		to := filepath.Join(folder, e.Name())
		if _, err := os.Stat(to); err == nil {
			return moves, fmt.Errorf("%s is already in %s", e.Name(), filepath.Base(folder))
		}
		if err := os.Rename(from, to); err != nil {
			return moves, err
		}
		moves = append(moves, Move{From: from, To: to})
	}
	return moves, nil
}
