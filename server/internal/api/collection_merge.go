package api

import (
	"net/http"

	"lumiere-server/internal/store"
)

// Merge is POST /Lumiere/Collections/{id}/MergeInto/{target}: the members of
// one collection join another, and the first is deleted. For the pairs Library
// Health finds — two "Batman Collection"s, a misspelt copy made by hand. The
// target keeps its name and artwork; nothing is lost but the duplicate.
func (h ContainerHandler) Merge(w http.ResponseWriter, r *http.Request) {
	from := store.NormalizeID(r.PathValue("id"))
	into := store.NormalizeID(r.PathValue("target"))
	if from == "" || into == "" || from == into || !h.Store.IsContainer(from) || !h.Store.IsContainer(into) {
		writeJSON(w, http.StatusNotFound, errorBody{"no such collections"})
		return
	}
	moved, err := h.Store.MergeCollection(from, into)
	if err != nil {
		h.Log.Error("container: could not merge", "from", from, "into", into, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not merge"})
		return
	}
	h.refreshPoster(into)
	h.Log.Info("container: merged", "from", from, "into", into, "added", moved)
	writeJSON(w, http.StatusOK, map[string]int{"Added": moved})
}
