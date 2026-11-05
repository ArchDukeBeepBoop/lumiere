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

func TestACollectionTakesATitlesPosterAsItsOwn(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	images := t.TempDir()
	poster := filepath.Join(images, "show.jpg")
	os.WriteFile(poster, []byte("show poster"), 0o644)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'BoxSet', 'Hoshi', 1), ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Series', 'Hoshi Twins', 1)`)
	s.SetImage("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Primary", poster, "t1", 0)
	s.SetItemValue("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "art:mosaic", "anilist")
	h := ArtworkHandler{Store: s, ImageDir: images, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /Lumiere/Items/{id}/Images/{kind}/From/{source}", h.CopyFrom)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("POST", "/Lumiere/Items/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Images/Primary/From/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", nil))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var path string
	s.DB.QueryRow(`SELECT path FROM image WHERE item_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' AND kind = 'Primary'`).Scan(&path)
	if data, _ := os.ReadFile(path); string(data) != "show poster" || path == poster {
		t.Fatalf("the collection has its own copy: %q", path)
	}
	if s.ItemValue("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "art:mosaic") != "" {
		t.Fatal("a chosen picture is not the server's to repaint")
	}
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("POST", "/Lumiere/Items/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Images/Backdrop/From/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("a picture the title lacks: %d", rec.Code)
	}
}
