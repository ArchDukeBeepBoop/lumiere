package api

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"lumiere-server/internal/store"
)

func TestWidgetFeedKeepsPrivateTitlesOutAndAnswersOnlyThisMac(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC().Format(time.RFC3339)
	for _, l := range [][2]string{{"vFilms", "fFilms"}, {"vPriv", "fPriv"}} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'CollectionFolder', ?, 1)`, l[0], l[0])
		s.DB.Exec(`INSERT INTO library_folder (view_id, folder_id) VALUES (?, ?)`, l[0], l[1])
	}
	s.SetMeta(metaPrivateLibraries, "vPriv")
	for _, f := range [][3]string{{"open", "Open Film", "fFilms"}, {"secret", "Secret Film", "fPriv"}} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, library_id, runtime_ticks) VALUES (?, 'Movie', ?, 0, ?, 1000000000)`, f[0], f[1], f[2])
		s.DB.Exec(`INSERT INTO user_data (item_id, position_ticks, last_played, updated_at) VALUES (?, 300000000, ?, ?)`, f[0], now, now)
	}
	mux, authed := http.NewServeMux(), http.NewServeMux()
	WidgetHandler{Store: s, Images: func(http.ResponseWriter, *http.Request) {}}.Register(mux, authed)

	get := func(remote string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("GET", "/Lumiere/Widget", nil)
		req.RemoteAddr = remote
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}
	rec := get("127.0.0.1:5000")
	if !strings.Contains(rec.Body.String(), "Open Film") || strings.Contains(rec.Body.String(), "Secret") {
		t.Fatalf("feed: %s", rec.Body)
	}
	if rec := get("192.168.50.9:5000"); rec.Code != http.StatusForbidden {
		t.Fatalf("another machine got %d", rec.Code)
	}
	s.SetMeta(metaWidgetOff, "1")
	if rec := get("127.0.0.1:5000"); strings.Contains(rec.Body.String(), "Open Film") {
		t.Fatalf("switched off but listed: %s", rec.Body)
	}
}
