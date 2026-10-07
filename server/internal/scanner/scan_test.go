package scanner

import (
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func testScanner(t *testing.T) *Scanner {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	// No probe: these are about what gets filed where, and a two-byte fixture
	// has nothing for ffprobe to read anyway.
	return &Scanner{Store: s, Log: slog.New(slog.DiscardHandler)}
}

// A tree shaped like the real one, with files large enough to be taken
// seriously — the walk drops anything under a megabyte as a stub.
func makeTree(t *testing.T, files ...string) string {
	t.Helper()
	root := t.TempDir()
	body := make([]byte, minimumMediaBytes+1)
	for _, name := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, body, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestScanBuildsSeriesAndSeasons(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t,
		"Gallery Fake/Season 1/Gallery Fake - 1x01 - One.mkv",
		"Gallery Fake/Season 1/Gallery Fake - 1x02 - Two.mkv",
		"Gallery Fake/Season 2/Gallery Fake - 2x01 - Three.mkv",
	)

	result, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.Files != 3 || result.Added != 3 {
		t.Fatalf("result = %+v, want 3 files added", result)
	}

	var series, seasons, episodes int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Series'`).Scan(&series)
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Season'`).Scan(&seasons)
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Episode'`).Scan(&episodes)
	if series != 1 || seasons != 2 || episodes != 3 {
		t.Errorf("built %d series, %d seasons, %d episodes; want 1, 2, 3", series, seasons, episodes)
	}

	// The episode knows where it belongs, which is the whole point of building
	// the parents at all.
	var seasonNumber, episodeNumber int
	if err := s.Store.DB.QueryRow(
		`SELECT parent_index_number, index_number FROM item
		 WHERE type='Episode' AND name LIKE '%Two%'`,
	).Scan(&seasonNumber, &episodeNumber); err != nil {
		t.Fatal(err)
	}
	if seasonNumber != 1 || episodeNumber != 2 {
		t.Errorf("numbering = S%dE%d, want S1E2", seasonNumber, episodeNumber)
	}
}

func TestScanIsIdempotent(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t, "Show/Season 1/Show - 1x01.mkv")

	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	// The second pass must add nothing. A scanner that re-adds is a scanner
	// that doubles the library every time it runs.
	second, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if second.Added != 0 {
		t.Errorf("second pass added %d, want 0", second.Added)
	}

	var items int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Episode'`).Scan(&items)
	if items != 1 {
		t.Errorf("%d episodes after two scans, want 1", items)
	}
}

func TestScanJoinsAShowJellyfinAlreadyImported(t *testing.T) {
	s := testScanner(t)
	// Jellyfin's row, with its own id — the case that decides whether the two
	// sources cooperate or produce two copies of every show.
	if _, err := s.Store.DB.Exec(`
		INSERT INTO item (id, type, name, library_id, is_folder)
		VALUES ('jellyfin-id', 'Series', 'Show', 'lib', 1)`); err != nil {
		t.Fatal(err)
	}

	root := makeTree(t, "Show/Season 1/Show - 1x01.mkv")
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}

	var series int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Series'`).Scan(&series)
	if series != 1 {
		t.Errorf("%d series, want the scanner to have joined the existing one", series)
	}
	var parent string
	s.Store.DB.QueryRow(`SELECT series_id FROM item WHERE type='Episode'`).Scan(&parent)
	if parent != "jellyfin-id" {
		t.Errorf("episode filed under %q, want jellyfin-id", parent)
	}
}

func TestScanNeverAddsAFileTwiceUnderTwoIDs(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t, "Movie (1999)/Movie (1999).mkv")
	path := filepath.Join(root, "Movie (1999)/Movie (1999).mkv")

	// Jellyfin knows this file, under its own id. Matching by path is what
	// stops the scanner shipping a second copy of it.
	if _, err := s.Store.DB.Exec(`
		INSERT INTO item (id, type, name, library_id, path)
		VALUES ('jellyfin-movie', 'Movie', 'Movie', 'lib', ?)`, path); err != nil {
		t.Fatal(err)
	}

	result, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.Added != 0 {
		t.Errorf("added %d, want 0 — the file was already catalogued", result.Added)
	}
}

func TestScanRefusesToRemoveMostOfALibrary(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t, "Show/Season 1/Show - 1x01.mkv")
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}

	// Half the library gone at once is a drive that did not come up, which
	// looks identical to a deletion and must be read as the safe one.
	if _, err := s.Store.DB.Exec(`
		INSERT INTO item (id, type, name, library_id, path, size)
		VALUES ('gone', 'Episode', 'Gone', 'lib', '/nowhere/gone.mkv', 5)`); err != nil {
		t.Fatal(err)
	}

	result, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.Missing != 1 || result.Removed != 0 {
		t.Errorf("missing = %d removed = %d, want 1 and 0", result.Missing, result.Removed)
	}
	var stillThere int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE id='gone'`).Scan(&stillThere)
	if stillThere != 1 {
		t.Error("a majority of a library missing must be reported, never removed")
	}
}

func TestScanRemovesAFewMissingFiles(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t,
		"Show/Season 1/Show - 1x01.mkv", "Show/Season 1/Show - 1x02.mkv",
		"Show/Season 1/Show - 1x03.mkv", "Show/Season 1/Show - 1x04.mkv",
	)
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(root, "Show/Season 1/Show - 1x04.mkv")); err != nil {
		t.Fatal(err)
	}

	result, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.Removed != 1 || result.Missing != 0 {
		t.Errorf("removed = %d missing = %d, want 1 and 0", result.Removed, result.Missing)
	}
	var left int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Episode'`).Scan(&left)
	if left != 3 {
		t.Errorf("episodes left = %d, want 3", left)
	}
}

func TestScanFollowsAMovedFile(t *testing.T) {
	s := testScanner(t)
	root := makeTree(t,
		"Old Name/Season 1/Show - 1x01.mkv",
		"Old Name/Season 1/Show - 1x02.mkv",
		"Old Name/Season 1/Show - 1x03.mkv",
	)
	if _, err := s.ScanLibrary("lib", root, nil); err != nil {
		t.Fatal(err)
	}
	// Something only the old row has: a picture, and a watched tick.
	var oldID string
	s.Store.DB.QueryRow(`SELECT id FROM item WHERE path LIKE '%1x02.mkv'`).Scan(&oldID)
	if _, err := s.Store.DB.Exec(
		`INSERT INTO image (item_id, kind, path, tag) VALUES (?, 'Primary', '/art/still.jpg', 't')`, oldID,
	); err != nil {
		t.Fatal(err)
	}

	// The whole show is renamed on disk.
	if err := os.Rename(filepath.Join(root, "Old Name"), filepath.Join(root, "New Name")); err != nil {
		t.Fatal(err)
	}
	result, err := s.ScanLibrary("lib", root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.Moved != 3 || result.Removed != 0 || result.Added != 0 {
		t.Errorf("moved = %d removed = %d added = %d, want 3, 0, 0",
			result.Moved, result.Removed, result.Added)
	}

	// Same row, new path, picture intact.
	var path string
	var pictures int
	s.Store.DB.QueryRow(`SELECT path FROM item WHERE id = ?`, oldID).Scan(&path)
	s.Store.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = ?`, oldID).Scan(&pictures)
	if filepath.Base(filepath.Dir(filepath.Dir(path))) != "New Name" {
		t.Errorf("row did not follow the move: %s", path)
	}
	if pictures != 1 {
		t.Error("the moved file lost its picture")
	}
	var episodes int
	s.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Episode'`).Scan(&episodes)
	if episodes != 3 {
		t.Errorf("episodes = %d, want 3 — a move must not leave a duplicate", episodes)
	}
}

func TestScanOnAMountThatIsNotThere(t *testing.T) {
	s := testScanner(t)
	// The case the whole no-delete rule exists for: an unmounted volume must
	// be an error, not an empty library.
	if _, err := s.ScanLibrary("lib", "/Volumes/NoSuchDriveHere", nil); err == nil {
		t.Error("want an error for a root that does not exist")
	}
}
