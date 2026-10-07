package api

import (
	"context"
	"net/http"
	"time"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// Filling collections from the film series they stand for, and keeping the
// movie-database answers fresh so no one waits on them.
//
// 41 collections arrived from Jellyfin with a movie-database series id and
// nothing in them. The series' film list is exactly what they should hold,
// matched to this library by each film's own movie-database id. Only films
// that are here are added; nothing is ever removed.

// FillFromSeries adds, to every collection with a series id, the films of
// that series this library has and the collection lacks. Returns how many.
func (h CollectionSuggestHandler) FillFromSeries(ctx context.Context, refresh bool) int {
	h.identifyEmpty(ctx)
	series := h.lookUp(ctx, h.seriesOfCollections(), refresh)
	added := 0
	for _, c := range h.Store.CollectionsWithSeries() {
		info, ok := series[c.TmdbID]
		if !ok {
			continue
		}
		var ids []string
		for _, part := range info.Parts {
			ids = append(ids, h.Store.ItemsWithTmdb(part.ID)...)
		}
		n, err := h.Store.AddMissingLinks(c.ID, ids)
		if err == nil && n > 0 {
			added += n
			h.Log.Info("collections: filled from film series", "name", c.Name, "added", n)
		}
	}
	return added
}

func (h CollectionSuggestHandler) seriesOfCollections() []store.TmdbGroup {
	var groups []store.TmdbGroup
	for _, c := range h.Store.CollectionsWithSeries() {
		groups = append(groups, store.TmdbGroup{TmdbID: c.TmdbID})
	}
	g, _ := h.Store.TmdbGroups()
	return append(groups, g...)
}

// KeepFresh refreshes every cached series overnight — names, film lists,
// what is missing — then fills collections from them. The first pass runs a
// few minutes after start, so the first suggestion scan of the day is
// instant rather than a minute of lookups.
func (h CollectionSuggestHandler) KeepFresh() {
	go func() {
		time.Sleep(3 * time.Minute)
		for {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
			n := h.FillFromSeries(ctx, true)
			made, adopted := h.AutoCollections(ctx)
			cancel()
			h.Log.Info("collections: overnight refresh", "filled", n, "made", made, "adopted", adopted)
			time.Sleep(24 * time.Hour)
		}
	}()
}

// identifyEmpty gives an empty collection with no series id one, by looking
// its name up — "Predator Collection" is the movie database's "Predator
// Collection". Exact names only; see metadata.SearchCollection. Asked once
// per collection: a name with no match is remembered as such.
func (h CollectionSuggestHandler) identifyEmpty(ctx context.Context) {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		return
	}
	tmdb := metadata.NewTMDB(token)
	for _, c := range h.Store.EmptyCollectionsWithoutSeries() {
		id, err := tmdb.SearchCollection(ctx, c.Name)
		if err != nil {
			return
		}
		if id == "" {
			h.Store.SetItemValue(c.ID, "tmdb_collection:searched", "1")
			continue
		}
		h.Store.SetItemValue(c.ID, "tmdb_collection", id)
		h.Log.Info("collections: found its film series by name", "name", c.Name, "tmdb", id)
	}
}

// Fill is POST /Lumiere/Collections/Fill — the overnight pass, now, for the
// Library Health button beside "Collections with nothing in them".
func (h CollectionSuggestHandler) Fill(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Minute)
	defer cancel()
	n := h.FillFromSeries(ctx, false)
	h.Log.Info("collections: filled on request", "added", n)
	writeJSON(w, http.StatusOK, map[string]int{"Added": n})
}
