package api

import (
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// SeriesNext is GET /Lumiere/Collections/NextUp — the next film in each film
// series under way, for Home's "Continue the Series" shelf. See store.SeriesNext.
func (h ContainerHandler) SeriesNext(w http.ResponseWriter, r *http.Request) {
	ids, err := h.Store.SeriesNext(40)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	out := jellyfin.ItemsResponse{Items: []jellyfin.BaseItem{}}
	if len(ids) > 0 {
		q := queryFrom(r.URL.Query())
		q.IDs = ids
		q.Recursive = true
		items, _, err := h.Store.Items(q)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
			return
		}
		byID := map[string]store.Item{}
		for _, it := range items {
			byID[it.ID] = it
		}
		var ordered []store.Item
		for _, id := range ids {
			if it, ok := byID[id]; ok {
				ordered = append(ordered, it)
			}
		}
		out.Items = h.Items.wire(ordered)
	}
	out.TotalRecordCount = len(out.Items)
	writeJSON(w, http.StatusOK, out)
}

// NextAfter is GET /Lumiere/Collections/NextAfter/{id}: the next film in the
// film's collection, for "Next in Alien Collection: Aliens" on its page.
// 204 when there is none.
func (h ContainerHandler) NextAfter(w http.ResponseWriter, r *http.Request) {
	next, name := h.Store.NextInCollection(store.NormalizeID(r.PathValue("id")))
	if next == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"Id": next, "Collection": name})
}
