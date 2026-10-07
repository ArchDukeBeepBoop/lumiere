package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestSuggestionsGroupFilmSeriesAndFillExistingCollections(t *testing.T) {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "data"))
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range [][3]string{{"a1", "Alien", "8091"}, {"a2", "Aliens", "8091"}, {"p1", "Predator", "399"}, {"p2", "Predators", "399"}, {"x", "Solo", "77"}} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'Movie', ?, 0)`, row[0], row[1])
		s.SetItemValue(row[0], "provider:TmdbCollection", row[2])
	}
	// An existing Predator collection that already holds one of the two.
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('pc', 'BoxSet', 'Predator Collection', 1)`)
	s.SetItemValue("pc", "tmdb_collection", "399")
	s.AddLinks("pc", []string{"p1"})

	h := CollectionSuggestHandler{Store: s, DataDir: dir, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	rec := httptest.NewRecorder()
	h.Suggestions(rec, httptest.NewRequest("GET", "/Lumiere/Collections/Suggestions", nil))
	var got []collectionSuggestion
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err, rec.Body.String())
	}
	if len(got) != 2 {
		t.Fatalf("got %d suggestions, want Alien (new) and Predator (fill): %+v", len(got), got)
	}
	for _, g := range got {
		switch g.TmdbId {
		case "8091":
			if g.CollectionId != "" || len(g.AddIds) != 2 || g.Name != "Alien Collection" {
				t.Errorf("new series wrong: %+v", g)
			}
		case "399":
			if g.CollectionId != "pc" || len(g.AddIds) != 1 || g.AddIds[0] != "p2" {
				t.Errorf("existing collection should gain only p2: %+v", g)
			}
		default:
			t.Errorf("a lone film was suggested: %+v", g)
		}
	}
}
