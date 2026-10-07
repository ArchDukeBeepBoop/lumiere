package media

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestAnEditedFileGetsANewFrameAndAMovedOneKeepsIt(t *testing.T) {
	db := artDB(t)
	db.Exec(`CREATE TABLE item_value (item_id TEXT, kind TEXT, value TEXT, PRIMARY KEY (item_id, kind, value))`)
	dir := t.TempDir()
	video := filepath.Join(dir, "a.mkv")
	os.WriteFile(video, make([]byte, 100), 0o644)
	frame := filepath.Join(dir, "frames", "a.jpg")
	os.MkdirAll(filepath.Dir(frame), 0o755)
	os.WriteFile(frame, []byte("x"), 0o644)
	db.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES ('a', 'Video', 'A', ?, 0)`, video)
	db.Exec(`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('a', 'Primary', 0, ?, 't')`, frame)

	// First sight: adopted, not retaken.
	if got, _ := changedFrames(db, 10); len(got) != 0 {
		t.Fatalf("a frame with no fingerprint was retaken: %v", got)
	}
	// Moved: same size and time, new path. Kept.
	moved := filepath.Join(dir, "sub", "a.mkv")
	os.MkdirAll(filepath.Dir(moved), 0o755)
	os.Rename(video, moved)
	db.Exec(`UPDATE item SET path = ? WHERE id = 'a'`, moved)
	if got, _ := changedFrames(db, 10); len(got) != 0 {
		t.Fatalf("a moved file lost its frame: %v", got)
	}
	// Edited in place: a different file under the same name. Retaken.
	os.WriteFile(moved, make([]byte, 250), 0o644)
	later := time.Now().Add(time.Hour)
	os.Chtimes(moved, later, later)
	if got, _ := changedFrames(db, 10); len(got) != 1 {
		t.Fatalf("an edited file kept its old frame")
	}
}

func TestAFailureIsRememberedUntilTheFileChanges(t *testing.T) {
	db := artDB(t)
	db.Exec(`CREATE TABLE item_value (item_id TEXT, kind TEXT, value TEXT, PRIMARY KEY (item_id, kind, value))`)
	setFrameValue(db, "a", "frame:failed", failureMark("100:5"))
	if !failedBefore(db, "a", "100:5") {
		t.Error("the same broken file should be skipped")
	}
	if failedBefore(db, "a", "250:9") {
		t.Error("a changed file should be tried again")
	}
}
