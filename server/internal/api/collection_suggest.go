package api

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// CollectionSuggestHandler proposes collections from what the movie database
// says about the films here, and says which films a collection is missing.
//
// The client's own suggestion scan groups by shared tags and folder names,
// which finds anime franchises and misses film series; the movie database's
// "belongs to collection" is the other half and is exact. The ids are already
// on 513 titles here from the import, so the only network work is naming each
// series and listing its films — once each, cached.
type CollectionSuggestHandler struct {
	Store   *store.Store
	DataDir string
	Log     *slog.Logger
}

type missingFilm struct {
	Title string
	Year  int `json:",omitempty"`
}

type collectionSuggestion struct {
	Name         string
	TmdbId       string
	CollectionId string `json:",omitempty"`
	// Titles here to put in it: all of them for a new collection, the ones
	// not yet linked for an existing one.
	AddIds    []string
	HeldCount int
	Missing   []missingFilm
}

// Suggestions is GET /Lumiere/Collections/Suggestions.
func (h CollectionSuggestHandler) Suggestions(w http.ResponseWriter, r *http.Request) {
	groups, err := h.Store.TmdbGroups()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read the library"})
		return
	}
	series := h.lookUp(r.Context(), groups, false)
	held := h.Store.TmdbIDsHeld()
	out := []collectionSuggestion{}
	for _, g := range groups {
		s := collectionSuggestion{TmdbId: g.TmdbID, CollectionId: g.CollectionID, HeldCount: len(g.Members)}
		info, known := series[g.TmdbID]
		s.Name = info.Name
		if s.Name == "" {
			s.Name = g.FirstName + " Collection"
		}
		for _, m := range g.Members {
			if !g.Linked[m] {
				s.AddIds = append(s.AddIds, m)
			}
		}
		if known {
			for _, p := range info.Parts {
				// Unreleased or undated films are not missing yet.
				if !held[p.ID] && p.Year > 0 && p.Year <= time.Now().Year() {
					s.Missing = append(s.Missing, missingFilm{Title: p.Title, Year: p.Year})
				}
			}
		}
		// A lone film with no collection is not a suggestion yet.
		if g.CollectionID == "" && len(g.Members) < 2 {
			continue
		}
		out = append(out, s)
	}
	h.Log.Info("collections: suggestions", "series", len(groups), "offered", len(out), "named", len(series))
	writeJSON(w, http.StatusOK, out)
}

// lookUp names each series and lists its films, from the cache where it can
// and the movie database where it must, four at a time and within a budget:
// what does not come back in time is labelled from its first film and tried
// again next time.
//
// `refresh` asks again for everything, keeping the cached answer wherever the
// new one does not arrive — the overnight pass, which must never leave the
// cache emptier than it found it.
func (h CollectionSuggestHandler) lookUp(ctx context.Context, groups []store.TmdbGroup, refresh bool) map[string]metadata.TMDBCollection {
	out := map[string]metadata.TMDBCollection{}
	var need []string
	seen := map[string]bool{}
	for _, g := range groups {
		if seen[g.TmdbID] {
			continue
		}
		seen[g.TmdbID] = true
		if raw, _ := h.Store.Meta("tmdbcoll:" + g.TmdbID); raw != "" {
			var c metadata.TMDBCollection
			if json.Unmarshal([]byte(raw), &c) == nil {
				out[g.TmdbID] = c
				if !refresh {
					continue
				}
			}
		}
		need = append(need, g.TmdbID)
	}
	token := metadata.ReadToken(h.DataDir)
	if token == "" || len(need) == 0 {
		return out
	}
	tmdb := metadata.NewTMDB(token)
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	var mu sync.Mutex
	var wg sync.WaitGroup
	gate := make(chan struct{}, 4)
	for _, id := range need {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			gate <- struct{}{}
			defer func() { <-gate }()
			c, err := tmdb.Collection(ctx, id)
			if err != nil {
				return
			}
			raw, _ := json.Marshal(c)
			h.Store.SetMeta("tmdbcoll:"+id, string(raw))
			mu.Lock()
			out[id] = c
			mu.Unlock()
		}(id)
	}
	wg.Wait()
	return out
}
