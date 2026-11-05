package api

import (
	"io"
	"net/http"
	"os"
	"path/filepath"

	"lumiere-server/internal/store"
)

// CopyFrom is POST /Lumiere/Items/{id}/Images/{kind}/From/{source}: give an
// item another item's picture — a collection the poster or backdrop of one
// of its own titles, which is where a adult franchise's best artwork is,
// since no provider has any for the collection itself. Copied rather than
// shared, so replacing either later leaves the other as it was; and marked
// as chosen, so neither the franchise pass nor the mosaic paints over it.
func (h ArtworkHandler) CopyFrom(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	source := store.NormalizeID(r.PathValue("source"))
	kind := imageKind(r.PathValue("kind"))
	if itemID == "" || source == "" || kind == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"an item, a source and a kind"})
		return
	}
	var path string
	h.Store.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = ? AND idx = 0`, source, kind).Scan(&path)
	if path == "" {
		writeJSON(w, http.StatusNotFound, errorBody{"that title has no such picture"})
		return
	}
	f, err := os.Open(path)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorBody{"that picture's file is not there (is its drive unplugged?)"})
		return
	}
	defer f.Close()
	body, err := io.ReadAll(io.LimitReader(f, 25<<20))
	if err != nil || len(body) == 0 {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read that picture"})
		return
	}
	if err := h.store(itemID, kind, body, filepath.Ext(path)); err != nil {
		h.Log.Warn("artwork: copy failed", "item", itemID, "source", source, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save the picture"})
		return
	}
	// Chosen now, not made: the mosaic and the AniList pass leave it alone.
	h.Store.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = 'art:mosaic'`, itemID)
	w.WriteHeader(http.StatusNoContent)
}
