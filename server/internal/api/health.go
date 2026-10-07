package api

import (
	"encoding/json"
	"time"

	"log/slog"
	"lumiere-server/internal/scanner"
	"net/http"

	"lumiere-server/internal/store"
)

// HealthHandler is GET /Library/Health: what is wrong with the library, by
// kind, with a few examples of each. The fixes are the existing passes —
// POST /Library/Refresh and POST /Metadata/Run — so this only has to look.
type HealthHandler struct {
	Store *store.Store
	Log   *slog.Logger
}

func (h HealthHandler) Report(w http.ResponseWriter, r *http.Request) {
	issues, err := h.Store.Health()
	if err != nil {
		h.Log.Error("health: could not read the library", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read the library"})
		return
	}
	h.Store.AttachSince(issues)
	writeJSON(w, http.StatusOK, map[string]any{"Issues": issues})
}

// Dismiss is POST /Library/Health/Dismiss {"Kind": "...", "Key": "..."} —
// leave one finding alone from now on.
func (h HealthHandler) Dismiss(w http.ResponseWriter, r *http.Request) {
	var body struct{ Kind, Key string }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<12)).Decode(&body); err != nil ||
		body.Kind == "" || body.Key == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"a kind and a key"})
		return
	}
	if err := h.Store.DismissHealth(body.Kind, body.Key); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Restore is POST /Library/Health/Restore — bring every ignored finding back.
func (h HealthHandler) Restore(w http.ResponseWriter, r *http.Request) {
	n, err := h.Store.RestoreHealth()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not restore"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"Restored": n})
}

// Register adds the health routes.
func (h HealthHandler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /Library/Health", h.Report)
	mux.HandleFunc("POST /Library/Health/Dismiss", h.Dismiss)
	mux.HandleFunc("POST /Library/Health/Restore", h.Restore)
	mux.HandleFunc("POST /Library/Health/MoveMisfiled", h.MoveMisfiled)
	mux.HandleFunc("POST /Library/Health/UndoMove", h.UndoMove)
	mux.HandleFunc("POST /Library/Repairs/UndoSeating", h.UndoSeating)
	mux.HandleFunc("POST /Library/Health/FileTitles", h.FileTitles)
	mux.HandleFunc("POST /Library/Health/FileTitles/Undo", h.FileTitlesUndo)
}

// UndoSeating is POST /Library/Repairs/UndoSeating — puts back every episode
// the seating repair moved into a season, and removes the seasons it made.
// The way back from that one repair without restoring the whole database.
func (h HealthHandler) UndoSeating(w http.ResponseWriter, r *http.Request) {
	n, err := scanner.UndoSeating(h.Store.DB)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{err.Error()})
		return
	}
	h.Store.SetMeta(store.MetaRepairedAt, time.Now().UTC().Format(time.RFC3339))
	h.Log.Info("repair undone: seating", "episodes", n)
	writeJSON(w, http.StatusOK, map[string]any{"Restored": n})
}
