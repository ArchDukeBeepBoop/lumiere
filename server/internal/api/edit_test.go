package api

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"lumiere-server/internal/store"
)

func TestEditWritesTheEditedFieldsAndLocksThem(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, sort_name, overview, is_folder)
		VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Movie', 'Blade Runer', 'Blade Runer', 'old', 0)`); err != nil {
		t.Fatal(err)
	}
	h := EditHandler{Store: s, Log: slog.New(slog.NewTextHandler(os.Stderr, nil))}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /Items/{id}", h.Edit)

	// What the app posts: the whole item back, with the edited keys changed.
	body := `{"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"Blade Runner","Overview":"A new one","ProductionYear":1982,
	          "Genres":["Science Fiction","Noir"],"Studios":[{"Name":"Warner Bros."}],
	          "LockedFields":["Name","Overview"]}`
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("POST", "/Items/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", strings.NewReader(body)))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}

	var name, sortName, overview string
	var year int
	s.DB.QueryRow(`SELECT name, sort_name, overview, production_year FROM item WHERE id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'`).
		Scan(&name, &sortName, &overview, &year)
	if name != "Blade Runner" || sortName != "Blade Runner" || overview != "A new one" || year != 1982 {
		t.Errorf("got %q/%q/%q/%d", name, sortName, overview, year)
	}
	var genres, studios int
	s.DB.QueryRow(`SELECT count(*) FROM item_value WHERE item_id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' AND kind='genre'`).Scan(&genres)
	s.DB.QueryRow(`SELECT count(*) FROM item_value WHERE item_id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' AND kind='studio'`).Scan(&studios)
	if genres != 2 || studios != 1 {
		t.Errorf("genres %d studios %d", genres, studios)
	}
	if !s.IsLocked("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Overview") || s.IsLocked("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Genres") {
		t.Error("locks did not land on the named fields only")
	}

	// An unknown item is a 404 that says so, not a silent no-op.
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("POST", "/Items/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", strings.NewReader(`{}`)))
	if rec.Code != http.StatusNotFound {
		t.Errorf("unknown item: status %d", rec.Code)
	}
}
