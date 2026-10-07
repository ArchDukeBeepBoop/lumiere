package api

import (
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// UserViews is GET /UserViews — the library list, and the first thing Lumiere
// asks for after sign-in.
//
// It carries one field that changes how the entire app behaves: CollectionType.
// A library with none is a *folder library* (§5.4) — filenames as labels, a
// folder browser instead of a poster wall, MediaSources requested during sync.
// Two of the ten libraries here are folder libraries, and the value is not a
// column in Jellyfin's database: it lives inside the Data blob, which is why the
// importer digs it out by hand. Emitting it as an empty string rather than
// omitting it would turn both of them into poster walls.
// servableViews drops views this server cannot serve.
//
// Jellyfin returns 11 views here, not 12: it omits Live TV, because no tuner is
// configured. Live TV is out of scope for this server permanently (§8), so the
// row is dropped rather than offered as a library that opens onto nothing.
// Measured against the capture — matching its list exactly is Batch 3's
// acceptance, and a phantom library is the kind of difference a person notices
// before any test does.
func servableViews(items []store.Item) []store.Item {
	out := items[:0]
	for _, it := range items {
		if it.CollectionType == "livetv" {
			continue
		}
		out = append(out, it)
	}
	return out
}

func (h ItemsHandler) UserViews(w http.ResponseWriter, r *http.Request) {
	items, _, err := h.Store.Items(store.Query{
		Types:  []string{"CollectionFolder", "UserView"},
		SortBy: []string{"SortName"},
	})
	if err != nil {
		h.Log.Error("user views failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	items = servableViews(items)
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items: h.wire(items),
		// Counted after filtering, not before. TotalRecordCount is what paging
		// trusts, and a total that includes rows the response does not is how a
		// client waits forever for a twelfth library.
		TotalRecordCount: len(items),
	})
}
