package api

import (
	"log/slog"
	"net/http"

	"lumiere-server/internal/store"
)

// LinkedHandler is GET /Items/{id}/LinkedChapters: an episode's ordered
// edition, each borrowed range resolved to the item that carries it.
//
// Empty for a file with no ordered edition, which is almost every file — the
// client asks once per play and moves on. For the ones that have it, the
// answer is what mpv needs to play the release as its authors intended: the
// list of files whose segments the episode borrows from.
type LinkedHandler struct {
	Store *store.Store
	Log   *slog.Logger
}

func (h LinkedHandler) LinkedChapters(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	ranges, err := h.Store.LinkedChapters(id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read links"})
		return
	}
	if ranges == nil {
		ranges = []store.PlayRange{}
	}
	unresolved := 0
	for _, r := range ranges {
		if !r.Resolved {
			unresolved++
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"Ordered": len(ranges) > 0, "Ranges": ranges, "Unresolved": unresolved,
	})
}
