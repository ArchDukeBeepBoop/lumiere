package api

import (
	"context"
	"net/http"
	"time"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// SeriesSearch is GET /Lumiere/Collections/SeriesSearch?Name= — the film
// series a name finds, for "Find Its Series…" on a collection nothing matched.
func (h CollectionSuggestHandler) SeriesSearch(w http.ResponseWriter, r *http.Request) {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no TMDB key set on the server"})
		return
	}
	results, err := metadata.NewTMDB(token).SearchCollections(r.Context(), caseInsensitive(r.URL.Query())("Name"))
	if err != nil {
		writeJSON(w, http.StatusBadGateway, errorBody{"the movie database did not answer"})
		return
	}
	if results == nil {
		results = []metadata.CollectionMatch{}
	}
	writeJSON(w, http.StatusOK, results)
}

// SetSeries is POST /Lumiere/Collections/{id}/Series/{tmdb}: this collection
// is that film series. Remembered, and filled with the films of it here.
func (h CollectionSuggestHandler) SetSeries(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if !h.Store.IsContainer(id) {
		writeJSON(w, http.StatusNotFound, errorBody{"no such collection"})
		return
	}
	h.Store.SetItemValue(id, "tmdb_collection", r.PathValue("tmdb"))
	ctx, cancel := context.WithTimeout(r.Context(), time.Minute)
	defer cancel()
	// Identify: the series' name, synopsis, poster and backdrop too.
	if token := metadata.ReadToken(h.DataDir); token != "" {
		h.dress(ctx, metadata.NewTMDB(token), id, r.PathValue("tmdb"))
	}
	added := h.FillFromSeries(ctx, false)
	h.Log.Info("collections: series chosen by hand", "id", id, "tmdb", r.PathValue("tmdb"), "added", added)
	writeJSON(w, http.StatusOK, map[string]int{"Added": added})
}
