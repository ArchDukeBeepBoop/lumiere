package api

import (
	"encoding/json"
	"io"
	"net/http"

	"lumiere-server/internal/store"
)

// WatchOrder is GET /Lumiere/WatchOrder/{id}: the collection's
// watch order arranged by hand, {"Items": [ids]}, empty when none has been.
func (h ContainerHandler) WatchOrder(w http.ResponseWriter, r *http.Request) {
	ids, err := h.Store.WatchOrder(store.NormalizeID(r.PathValue("id")))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read the watch order"})
		return
	}
	writeJSON(w, http.StatusOK, map[string][]string{"Items": ids})
}

// SetWatchOrder is PUT /Lumiere/WatchOrder/{id} {"Items": [ids]}:
// the whole arrangement, replacing the last; an empty list clears it.
func (h ContainerHandler) SetWatchOrder(w http.ResponseWriter, r *http.Request) {
	var body struct{ Items []string }
	if err := json.NewDecoder(io.LimitReader(r.Body, 256<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	ids := make([]string, 0, len(body.Items))
	for _, id := range body.Items {
		ids = append(ids, store.NormalizeID(id))
	}
	if err := h.Store.SetWatchOrder(store.NormalizeID(r.PathValue("id")), ids); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save the watch order"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
