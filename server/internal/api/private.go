package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"lumiere-server/internal/store"
)

// PrivateHandler holds the apps' own privacy settings: which libraries are
// private, so the phone and TV keep them out of sight without being told twice,
// and which the naming pass does not look up on the movie database.
type PrivateHandler struct {
	Store *store.Store
}

const metaPrivateLibraries = "private_libraries"

// PrivateLibraries is GET /Lumiere/Private: {"Libraries": [...]}.
func (h PrivateHandler) PrivateLibraries(w http.ResponseWriter, r *http.Request) {
	raw, _ := h.Store.Meta(metaPrivateLibraries)
	list := []string{}
	if raw != "" {
		list = strings.Split(raw, ",")
	}
	writeJSON(w, http.StatusOK, map[string][]string{"Libraries": list})
}

// SetPrivateLibraries is POST /Lumiere/Private {"Libraries": [...]}.
func (h PrivateHandler) SetPrivateLibraries(w http.ResponseWriter, r *http.Request) {
	h.saveList(w, r, metaPrivateLibraries)
}

// SkipLookups is POST /Lumiere/Metadata/Skip {"Libraries": [...]}: libraries
// the naming pass does not look up on the movie database.
func (h PrivateHandler) SkipLookups(w http.ResponseWriter, r *http.Request) {
	h.saveList(w, r, store.MetaLookupSkipped)
}

func (h PrivateHandler) saveList(w http.ResponseWriter, r *http.Request, key string) {
	var body struct{ Libraries []string }
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"expected {\"Libraries\": [...]}"})
		return
	}
	if err := h.Store.SetMeta(key, strings.Join(body.Libraries, ",")); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
