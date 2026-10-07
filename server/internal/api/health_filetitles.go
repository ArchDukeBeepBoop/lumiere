package api

import "net/http"

// FileTitles is POST /Library/Health/FileTitles; FileTitlesUndo reverses it.
// See store.TitleAllFromFilenames.
func (h HealthHandler) FileTitles(w http.ResponseWriter, r *http.Request) {
	n, err := h.Store.TitleAllFromFilenames()
	if err != nil {
		h.Log.Error("file titles failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not rename"})
		return
	}
	h.Log.Info("repair: episodes titled from their filenames", "count", n)
	writeJSON(w, http.StatusOK, map[string]int{"Renamed": n})
}

func (h HealthHandler) FileTitlesUndo(w http.ResponseWriter, r *http.Request) {
	n, err := h.Store.UndoFileTitles()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not undo"})
		return
	}
	h.Log.Info("repair undone: file titles", "count", n)
	writeJSON(w, http.StatusOK, map[string]int{"Restored": n})
}
