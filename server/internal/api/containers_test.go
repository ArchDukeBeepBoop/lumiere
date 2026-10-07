package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

func TestCollectionsAreMadeFilledListedAndEmptied(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"a", "b"} {
		full := id + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		if _, err := s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'Movie', ?, 0)`, full, id); err != nil {
			t.Fatal(err)
		}
	}
	a, b := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	items := ItemsHandler{Store: s, Log: log}
	h := ContainerHandler{Store: s, Items: items, Log: log}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /Collections", h.Create("BoxSet"))
	mux.HandleFunc("POST /Collections/{id}/Items", h.Add)
	mux.HandleFunc("DELETE /Collections/{id}/Items", h.Remove)
	mux.HandleFunc("GET /Items", items.Items)
	mux.HandleFunc("DELETE /Items", h.DeleteItems)

	do := func(method, target string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(method, target, nil))
		return rec
	}
	list := func(parent string) int {
		rec := do("GET", "/Items?ParentId="+parent)
		var out jellyfin.ItemsResponse
		json.Unmarshal(rec.Body.Bytes(), &out)
		return len(out.Items)
	}

	rec := do("POST", "/Collections?Name=Cyberpunk&Ids="+a)
	if rec.Code != http.StatusOK {
		t.Fatalf("create: %d %s", rec.Code, rec.Body.String())
	}
	var made struct{ Id string }
	json.Unmarshal(rec.Body.Bytes(), &made)
	if n := list(made.Id); n != 1 {
		t.Errorf("after create: %d members, want 1", n)
	}
	if rec := do("POST", "/Collections/"+made.Id+"/Items?Ids="+b); rec.Code != http.StatusNoContent {
		t.Fatalf("add: %d", rec.Code)
	}
	if n := list(made.Id); n != 2 {
		t.Errorf("after add: %d members, want 2", n)
	}
	if rec := do("DELETE", "/Collections/"+made.Id+"/Items?Ids="+a); rec.Code != http.StatusNoContent {
		t.Fatalf("remove: %d", rec.Code)
	}
	if n := list(made.Id); n != 1 {
		t.Errorf("after remove: %d members, want 1", n)
	}
	// Deleting the collection must not delete the film.
	if rec := do("DELETE", "/Items?ids="+made.Id); rec.Code != http.StatusNoContent {
		t.Fatalf("delete: %d", rec.Code)
	}
	var films int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE type='Movie'`).Scan(&films)
	if films != 2 {
		t.Errorf("deleting a collection removed a film")
	}
	// And a film may never be deleted this way.
	if rec := do("DELETE", "/Items?ids="+a); rec.Code != http.StatusForbidden {
		t.Errorf("deleting media: %d, want 403", rec.Code)
	}
}
