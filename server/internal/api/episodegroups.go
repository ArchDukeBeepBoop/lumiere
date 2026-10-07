package api

import (
	"context"
	"encoding/json"
	"net/http"
	"sync/atomic"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// EpisodeGroups is GET /Shows/{seriesId}/EpisodeGroups — the alternative
// episode orders TMDB offers for a show, and which one is chosen.
func (h *MetadataHandler) EpisodeGroups(w http.ResponseWriter, r *http.Request) {
	enricher, tmdbID, ok := h.groupContext(w, r)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	groups, err := enricher.TMDB.EpisodeGroups(ctx, tmdbID)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, errorBody{err.Error()})
		return
	}
	// How well each order fits the folders on disk. A request per order, so
	// only a handful — the sheet shows every order a show has, rarely more
	// than five.
	seriesID := store.NormalizeID(r.PathValue("seriesId"))
	local := enricher.LocalSeasonSizes(seriesID)
	fits := map[string]float64{}
	for i, g := range groups {
		if i >= 8 {
			break
		}
		if sizes, err := enricher.TMDB.PartSizes(ctx, g.ID); err == nil {
			fits[g.ID] = metadata.Fit(local, sizes)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"Groups":   groups,
		"Selected": enricher.EpisodeGroup(seriesID),
		"Fits":     fits,
	})
}

// SetEpisodeGroup is POST /Shows/{seriesId}/EpisodeGroup {"Id": "..."} — ""
// for TMDB's own order. The show's episodes are released and a naming pass
// starts, so the new titles arrive without another click.
func (h *MetadataHandler) SetEpisodeGroup(w http.ResponseWriter, r *http.Request) {
	enricher, _, ok := h.groupContext(w, r)
	if !ok {
		return
	}
	var body struct{ Id string }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<12)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	seriesID := store.NormalizeID(r.PathValue("seriesId"))
	if err := enricher.SetEpisodeGroup(seriesID, body.Id); err != nil {
		h.Log.Error("metadata: could not set episode order", "series", seriesID, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save the order"})
		return
	}
	h.Log.Info("metadata: episode order chosen", "series", seriesID, "group", body.Id)
	h.Start()
	w.WriteHeader(http.StatusNoContent)
}

// groupContext is the enricher and the show's TMDB id, or an answer saying
// why there is neither.
func (h *MetadataHandler) groupContext(w http.ResponseWriter, r *http.Request) (*metadata.Enricher, string, bool) {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no TMDB key set on the server"})
		return nil, "", false
	}
	var tmdbID string
	h.Store.DB.QueryRow(`SELECT value FROM item_value WHERE item_id = ? AND kind = 'provider:Tmdb'`,
		store.NormalizeID(r.PathValue("seriesId"))).Scan(&tmdbID)
	if tmdbID == "" {
		writeJSON(w, http.StatusNotFound, errorBody{"this show is not matched to TMDB"})
		return nil, "", false
	}
	return &metadata.Enricher{
		Store: h.Store, TMDB: metadata.NewTMDB(token), ImageDir: h.ImageDir, Log: h.Log,
	}, tmdbID, true
}

// Frames is POST /Metadata/Frames — take a frame for every file with no
// picture now, rather than after the next naming pass. Answers at once; the
// frames arrive in the background, a few seconds each.
func (h *MetadataHandler) Frames(w http.ResponseWriter, r *http.Request) {
	// One pass at a time: two would take the same frames twice.
	if !framesRunning.CompareAndSwap(false, true) {
		w.WriteHeader(http.StatusAccepted)
		return
	}
	go func() {
		defer framesRunning.Store(false)
		taken, err := media.Frames(h.Store.DB, media.FindFFmpeg(), h.ImageDir, 500, h.Log)
		if err != nil {
			h.Log.Error("frames: on-demand pass failed", "error", err)
			return
		}
		h.Log.Info("frames: on-demand pass complete", "taken", taken)
	}()
	w.WriteHeader(http.StatusAccepted)
}

var framesRunning atomic.Bool
