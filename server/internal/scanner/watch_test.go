package scanner

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func tempRoot(t *testing.T) (Root, string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "Show", "Season 1"), 0o755); err != nil {
		t.Fatal(err)
	}
	return Root{Path: dir, Name: "Test"}, dir
}

// A file appearing changes the mtime of the directory holding it. That single
// fact is what the whole watcher rests on, so it is pinned first.
func TestANewFileChangesTheFingerprint(t *testing.T) {
	root, dir := tempRoot(t)
	before, ok := fingerprint([]Root{root})
	if !ok {
		t.Fatal("could not read a directory we just made")
	}

	// Filesystems store mtime at second or better granularity; a write in the
	// same tick as the read can leave the two indistinguishable.
	time.Sleep(1100 * time.Millisecond)
	if err := os.WriteFile(filepath.Join(dir, "Show", "Season 1", "ep1.mkv"),
		[]byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	after, ok := fingerprint([]Root{root})
	if !ok {
		t.Fatal("unreadable after a write")
	}
	if after == before {
		t.Fatal("a new file did not change the fingerprint")
	}
}

// A move is the case the scheduled scan handles badly and this is meant to
// catch: nothing is created or destroyed, only re-parented.
func TestMovingAFileChangesTheFingerprint(t *testing.T) {
	root, dir := tempRoot(t)
	from := filepath.Join(dir, "Show", "Season 1", "ep1.mkv")
	if err := os.WriteFile(from, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "Show", "Season 2"), 0o755); err != nil {
		t.Fatal(err)
	}
	before, _ := fingerprint([]Root{root})

	time.Sleep(1100 * time.Millisecond)
	if err := os.Rename(from, filepath.Join(dir, "Show", "Season 2", "ep1.mkv")); err != nil {
		t.Fatal(err)
	}
	after, _ := fingerprint([]Root{root})
	if after == before {
		t.Fatal("a moved file did not change the fingerprint")
	}
}

// Writing *into* an existing file is not a library change. A download finishing
// in place would otherwise trigger a scan on every flush.
func TestWritingToAFileDoesNotChangeTheFingerprint(t *testing.T) {
	root, dir := tempRoot(t)
	path := filepath.Join(dir, "Show", "Season 1", "ep1.mkv")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	before, _ := fingerprint([]Root{root})

	time.Sleep(1100 * time.Millisecond)
	if err := os.WriteFile(path, []byte("xxxxxxxxxx"), 0o644); err != nil {
		t.Fatal(err)
	}
	after, _ := fingerprint([]Root{root})
	if after != before {
		t.Error("growing a file looked like a library change")
	}
}

// The hazard worth more than the feature: this library lives on an external
// volume. Unmounting it makes every root vanish at once, which must read as
// "do not know" rather than as "the library was deleted" — the second would
// hand a scanner an empty disk and an existing database.
func TestAnUnreadableRootIsNotAnEmptyLibrary(t *testing.T) {
	root, _ := tempRoot(t)
	if _, ok := fingerprint([]Root{root}); !ok {
		t.Fatal("a readable root reported as unreadable")
	}

	gone := Root{Path: filepath.Join(t.TempDir(), "never-mounted"), Name: "Gone"}
	if _, ok := fingerprint([]Root{gone}); ok {
		t.Error("a missing root reported a usable fingerprint")
	}
	// And one missing root poisons the whole pass, rather than quietly
	// fingerprinting whatever is still mounted.
	if _, ok := fingerprint([]Root{root, gone}); ok {
		t.Error("a missing root was skipped instead of stopping the pass")
	}
}

// A file is also an unreadable root: a volume replaced by a stub, or a path
// that now names something else.
func TestARootThatIsNotADirectory(t *testing.T) {
	file := filepath.Join(t.TempDir(), "notadir")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, ok := fingerprint([]Root{{Path: file, Name: "File"}}); ok {
		t.Error("a plain file passed as a library root")
	}
}

// Nothing changing must produce the same number twice, or every tick is a scan.
func TestAQuietTreeIsStable(t *testing.T) {
	root, _ := tempRoot(t)
	first, _ := fingerprint([]Root{root})
	second, _ := fingerprint([]Root{root})
	if first != second {
		t.Fatal("the fingerprint is not stable on an unchanged tree")
	}
}
