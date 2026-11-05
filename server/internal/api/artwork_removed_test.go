package api

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestARemovedBackdropStaysRemovedUntilOneIsChosen(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	id := "cccccccccccccccccccccccccccccccc"
	images := t.TempDir()
	pic := filepath.Join(images, "b.jpg")
	os.WriteFile(pic, []byte("backdrop"), 0o644)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'Series', 'Show', 1)`, id)
	s.SetImage(id, "Backdrop", pic, "t1", 0)
	h := ArtworkHandler{Store: s, ImageDir: images, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	mux := http.NewServeMux()
	mux.HandleFunc("DELETE /Items/{id}/Images/{kind}", h.Delete)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("DELETE", "/Items/"+id+"/Images/Backdrop", nil))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status %d", rec.Code)
	}
	count := func() int {
		var n int
		s.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = ? AND kind = 'Backdrop'`, id).Scan(&n)
		return n
	}
	// An automatic pass filling what is missing — SetImage and a raw insert alike.
	s.SetImage(id, "Backdrop", pic, "auto", 0)
	s.DB.Exec(`INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?, 'Backdrop', 0, ?, 'raw')`, id, pic)
	if count() != 0 {
		t.Fatal("a removed backdrop is not put back by a pass")
	}
	if err := h.store(id, "Backdrop", []byte("mine"), ".jpg"); err != nil || count() != 1 {
		t.Fatalf("choosing one sets it again: %v %d", err, count())
	}
	// A pass writing over a chosen picture is ignored.
	s.SetImage(id, "Backdrop", pic, "auto", 0)
	var path string
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = 'Backdrop'`, id).Scan(&path)
	if filepath.Base(filepath.Dir(path)) != "chosen" {
		t.Fatalf("the choice stands: %q", path)
	}
}

func TestAChosenPictureDeletesTheOneItReplaces(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	id := "dddddddddddddddddddddddddddddddd"
	images := t.TempDir()
	old := filepath.Join(images, "metadata", id+"-primary.jpg")
	os.MkdirAll(filepath.Dir(old), 0o755)
	os.WriteFile(old, []byte("old poster"), 0o644)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'Movie', 'Film', 0)`, id)
	s.SetImage(id, "Primary", old, "t0", 0)
	h := ArtworkHandler{Store: s, ImageDir: images, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	if err := h.store(id, "Primary", []byte("new poster"), ".jpg"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatal("the replaced poster's file is deleted")
	}
}
