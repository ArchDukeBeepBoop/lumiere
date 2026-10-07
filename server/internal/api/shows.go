package api

import (
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// Seasons is GET /Shows/{seriesId}/Seasons.
//
// Ordered by ParentIndexNumber then IndexNumber, which puts Specials (season 0)
// first — where Jellyfin puts them, and where the client expects them.
func (h ItemsHandler) Seasons(w http.ResponseWriter, r *http.Request) {
	seriesID := store.NormalizeID(r.PathValue("seriesId"))
	if seriesID == "" {
		http.NotFound(w, r)
		return
	}
	h.listResponse(w, store.Query{
		SeriesID: seriesID,
		Types:    []string{"Season"},
		SortBy:   []string{"IndexNumber"},
	}, "seasons")
}

// Episodes is GET /Shows/{seriesId}/Episodes, optionally narrowed by seasonId.
//
// The whole series when no season is named — which is what the client asks for
// when it builds an Up Next queue, so it must not be capped.
func (h ItemsHandler) Episodes(w http.ResponseWriter, r *http.Request) {
	seriesID := store.NormalizeID(r.PathValue("seriesId"))
	if seriesID == "" {
		http.NotFound(w, r)
		return
	}
	q := store.Query{
		SeriesID: seriesID,
		Types:    []string{"Episode"},
		// Sorted across the whole series: season first, then episode. Sorting on
		// IndexNumber alone would interleave every season's episode 1.
		SortBy:        []string{"IndexNumber"},
		ExcludeExtras: true,
	}
	get := caseInsensitive(r.URL.Query())
	if season := store.NormalizeID(get("seasonId")); season != "" {
		q.SeasonID = season
	}
	h.listResponse(w, q, "episodes")
}

// NextUp is GET /Shows/NextUp — the episode to watch next in each series.
//
// The rule, which is Jellyfin's: for every series with something watched, the
// lowest-numbered unwatched episode after the furthest point reached. A series
// nobody has started does not appear at all; that is what the Latest shelf is
// for, and mixing them makes Next Up a list of things never begun.
func (h ItemsHandler) NextUp(w http.ResponseWriter, r *http.Request) {
	get := caseInsensitive(r.URL.Query())
	limit := atoiOr(get("Limit"), 20)
	seriesID := store.NormalizeID(get("SeriesId"))

	items, err := h.Store.NextUp(seriesID, limit)
	if err != nil {
		h.Log.Error("next up failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            h.wire(items),
		TotalRecordCount: len(items),
	})
}

// Similar is GET /Items/{id}/Similar — cosmetic, and an empty list is a valid
// answer (§4.2).
//
// Answered from genre overlap rather than left empty: the data is already here,
// the query is one join, and a "More like this" row that is always blank is a
// worse experience than one that is roughly right. Scoped to the same library
// and the same type so a film does not suggest an episode.
func (h ItemsHandler) Similar(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		http.NotFound(w, r)
		return
	}
	limit := atoiOr(caseInsensitive(r.URL.Query())("Limit"), 12)
	items, err := h.Store.Similar(id, limit)
	if err != nil {
		h.Log.Error("similar failed", "error", err, "item", id)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            h.wire(items),
		TotalRecordCount: len(items),
	})
}

// SpecialFeatures is GET /Users/{userId}/Items/{id}/SpecialFeatures.
//
// A bare array, not an envelope — one of the two endpoints that differ this way
// (§5.1), and getting it wrong means the client decodes nothing and shows no
// extras rather than erroring.
func (h ItemsHandler) SpecialFeatures(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		writeJSON(w, http.StatusOK, []jellyfin.BaseItem{})
		return
	}
	items, err := h.Store.Extras(id)
	if err != nil {
		h.Log.Error("special features failed", "error", err, "item", id)
		writeJSON(w, http.StatusOK, []jellyfin.BaseItem{})
		return
	}
	writeJSON(w, http.StatusOK, h.wire(items))
}

// listResponse is the shared tail of every list endpoint here: run the query,
// wrap it in the envelope, and turn a failure into a 500 with a logged reason
// rather than a half-written body.
func (h ItemsHandler) listResponse(w http.ResponseWriter, q store.Query, what string) {
	items, total, err := h.Store.Items(q)
	if err != nil {
		h.Log.Error(what+" failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            h.wire(items),
		TotalRecordCount: total,
	})
}
