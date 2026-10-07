package api

import (
	"log/slog"
	"net/http"
	"strings"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
)

// RemovalHandler: taking content out of the library.
//
//	DELETE /Items/{id}                 — remove; files untouched, restorable
//	DELETE /Items/{id}?permanent=true  — to the Trash, and gone from here
//	POST   /Items/{id}/Restore
//	GET    /Items/Removed
//
// The plural DELETE /Items?ids= stays what it was: collections and playlists
// only. Media leaves through this route or not at all, and the two operations
// are separate words so nobody reaches for the wrong one.
type RemovalHandler struct {
	Store *store.Store
	Log   *slog.Logger
}

func (h RemovalHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"bad item id"})
		return
	}
	permanent := strings.EqualFold(caseInsensitive(r.URL.Query())("permanent"), "true")
	if !permanent {
		moved, err := h.Store.Remove(id)
		if err != nil {
			h.Log.Error("remove failed", "item", id, "error", err)
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not remove"})
			return
		}
		if moved == 0 {
			writeJSON(w, http.StatusNotFound, errorBody{"no such item"})
			return
		}
		h.Log.Info("removed from library", "item", id, "rows", moved)
		writeJSON(w, http.StatusOK, map[string]int{"Removed": moved})
		return
	}

	ids, paths, err := h.Store.PathsUnder(id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not list files"})
		return
	}
	if len(ids) == 0 {
		writeJSON(w, http.StatusNotFound, errorBody{"no such item"})
		return
	}
	// Files first, rows second. If the Trash refuses — a network share with
	// no Trash — nothing has been dropped from the catalogue and the answer
	// says why. Longest paths first, so a file inside a folder that is also
	// listed goes before the folder does; a folder already moved takes its
	// contents with it and the later moves simply find nothing there.
	trashed := 0
	record := trashRecord{UserData: h.watchStateOf(ids)}
	for _, path := range longestFirst(paths) {
		target, err := media.Trash(path)
		if err == nil {
			record.Moves = append(record.Moves, trashMove{From: path, To: target})
		}
		if err != nil {
			if strings.Contains(err.Error(), "no such file") {
				continue
			}
			h.Log.Error("trash failed", "path", path, "error", err)
			writeJSON(w, http.StatusConflict, errorBody{err.Error()})
			return
		}
		trashed++
	}
	if err := h.Store.Purge(ids); err != nil {
		h.Log.Error("purge failed", "item", id, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"files moved to the Trash but the catalogue could not be updated"})
		return
	}
	rememberTrash(record)
	h.Log.Info("deleted to trash", "item", id, "files", trashed, "rows", len(ids))
	writeJSON(w, http.StatusOK, map[string]int{"Trashed": trashed, "Removed": len(ids)})
}

func (h RemovalHandler) Restore(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	restored, err := h.Store.Restore(id)
	if err != nil || restored == 0 {
		writeJSON(w, http.StatusNotFound, errorBody{"nothing to restore"})
		return
	}
	h.Log.Info("restored", "item", id, "rows", restored)
	writeJSON(w, http.StatusOK, map[string]int{"Restored": restored})
}

func (h RemovalHandler) Removed(w http.ResponseWriter, r *http.Request) {
	items, err := h.Store.Removed()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not list"})
		return
	}
	if items == nil {
		items = []store.RemovedItem{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"Items": items, "TotalRecordCount": len(items)})
}

func longestFirst(paths []string) []string {
	out := append([]string(nil), paths...)
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && len(out[j]) > len(out[j-1]); j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}
