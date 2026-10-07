package api

import (
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestUndoPutsTheFileAndItsHistoryBack(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	dir := t.TempDir()
	from := filepath.Join(dir, "Show", "ep.mkv")
	to := filepath.Join(dir, ".Trash", "ep.mkv")
	os.MkdirAll(filepath.Dir(from), 0o755)
	os.MkdirAll(filepath.Dir(to), 0o755)
	os.WriteFile(to, []byte("video"), 0o644)

	rememberTrash(trashRecord{
		Moves:    []trashMove{{From: from, To: to}},
		UserData: []map[string]any{{"item_id": "ep", "played": int64(1), "updated_at": "x"}},
	})
	h := RemovalHandler{Store: s, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	w := httptest.NewRecorder()
	h.Untrash(w, httptest.NewRequest("POST", "/Items/Untrash", nil))

	if w.Code != 200 {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	if _, err := os.Stat(from); err != nil {
		t.Error("the file is not back where it was")
	}
	var played int
	s.DB.QueryRow(`SELECT played FROM user_data WHERE item_id = 'ep'`).Scan(&played)
	if played != 1 {
		t.Error("the watch history did not come back")
	}
	// Once only: a second Undo has nothing to do.
	w = httptest.NewRecorder()
	h.Untrash(w, httptest.NewRequest("POST", "/Items/Untrash", nil))
	if w.Code != 410 {
		t.Errorf("second undo = %d, want 410", w.Code)
	}
}
