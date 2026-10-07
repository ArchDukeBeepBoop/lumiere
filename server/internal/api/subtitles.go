package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
	"lumiere-server/internal/subs"
)

// Finding a subtitle for a file that has none, and making it land on the
// right line.
//
// Two jobs that are usually two programs — a downloader and ffsubsync — and
// one workflow in practice: the subtitle you find is cut for a different
// release, so the fetch that does not also sync is a fetch that hands you a
// file to fix by hand.

type SubtitleHandler struct {
	Store   *store.Store
	DataDir string
	Log     *slog.Logger
}

// Register adds the subtitle routes.
func (h SubtitleHandler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /Subtitles/Status", h.Status)
	mux.HandleFunc("POST /Subtitles/Key", h.SetKey)
	mux.HandleFunc("GET /Items/{id}/RemoteSubtitles", h.Search)
	mux.HandleFunc("POST /Items/{id}/RemoteSubtitles/{fileId}", h.Download)
	mux.HandleFunc("POST /Items/{id}/Subtitles/{index}/Sync", h.Sync)
	mux.HandleFunc("POST /Shows/{seriesId}/Subtitles/Queue", h.Queue)
	mux.HandleFunc("GET /Subtitles/Queue", h.QueueStatus)
	mux.HandleFunc("POST /Subtitles/Queue/Limit", h.SetDailyLimit)
	mux.HandleFunc("POST /Subtitles/Queue/Retry", h.RetryFailed)
	// The queue's worker lives as long as the routes that feed it.
	go h.runQueue()
}

// Search is GET /Items/{id}/RemoteSubtitles?language=en.
func (h SubtitleHandler) Search(w http.ResponseWriter, r *http.Request) {
	item, ok := h.itemFor(w, r)
	if !ok {
		return
	}
	key := subs.ReadKey(h.DataDir)
	if key == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no subtitle provider key set on the server"})
		return
	}
	language := r.URL.Query().Get("language")
	if language == "" {
		language = "en"
	}

	query := h.queryFor(item, language)

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	found, err := subs.New(key).Search(ctx, query)
	if err != nil {
		h.Log.Info("subtitles: search failed", "item", item.Name, "error", err)
		writeJSON(w, http.StatusBadGateway, errorBody{err.Error()})
		return
	}
	if found == nil {
		found = []subs.Candidate{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"Results": found})
}

// Download is POST /Items/{id}/RemoteSubtitles/{fileId}, optionally
// ?sync=true. The subtitle is saved beside the video and registered as a
// stream, so everything downstream treats it as any other sidecar.
func (h SubtitleHandler) Download(w http.ResponseWriter, r *http.Request) {
	item, ok := h.itemFor(w, r)
	if !ok {
		return
	}
	fileID, err := strconv.Atoi(r.PathValue("fileId"))
	if err != nil || fileID <= 0 {
		writeJSON(w, http.StatusBadRequest, errorBody{"no subtitle named"})
		return
	}
	key := subs.ReadKey(h.DataDir)
	if key == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no subtitle provider key set on the server"})
		return
	}
	language := r.URL.Query().Get("language")
	if language == "" {
		language = "en"
	}

	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()
	text, extension, err := subs.New(key).Download(ctx, fileID)
	if err != nil {
		h.Log.Info("subtitles: download failed", "item", item.Name, "error", err)
		writeJSON(w, http.StatusBadGateway, errorBody{err.Error()})
		return
	}

	path := store.ExternalSubtitlePath(item.Path, language, extension)
	if err := os.WriteFile(path, text, 0o644); err != nil {
		h.Log.Error("subtitles: could not save", "path", path, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save the subtitle"})
		return
	}
	index, err := h.Store.AddExternalSubtitle(item.ID, path, language, "OpenSubtitles")
	if err != nil {
		h.Log.Error("subtitles: could not record", "item", item.ID, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not record the subtitle"})
		return
	}

	body := map[string]any{"Index": index, "Path": path}
	if r.URL.Query().Get("sync") == "true" {
		offset, confidence := h.sync(ctx, item.Path, path, maxShiftFrom(r))
		body["Offset"], body["Confidence"] = offset, confidence
	}
	writeJSON(w, http.StatusOK, body)
}

// Sync is POST /Items/{id}/Subtitles/{index}/Sync — align a subtitle the
// library already has against this file's audio.
func (h SubtitleHandler) Sync(w http.ResponseWriter, r *http.Request) {
	item, ok := h.itemFor(w, r)
	if !ok {
		return
	}
	index := atoiOr(r.PathValue("index"), -1)
	streams, err := h.Store.Streams(item.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read the streams"})
		return
	}
	path := ""
	for _, stream := range streams {
		if stream.Index == index && stream.Type == "Subtitle" {
			path = stream.Path
		}
	}
	if path == "" {
		// An in-band track. Extracting it to sync would be honest work, but
		// a track inside the file was cut for the file: it is already right,
		// and offering to fix it invites breaking it.
		writeJSON(w, http.StatusBadRequest, errorBody{"only an external subtitle can be synced"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
	defer cancel()
	offset, confidence := h.sync(ctx, item.Path, path, maxShiftFrom(r))
	writeJSON(w, http.StatusOK, map[string]any{
		"Offset": offset, "Confidence": confidence,
		"Trusted": confidence >= subs.MinConfidence,
	})
}

func (h SubtitleHandler) sync(ctx context.Context, video, subtitle string, maxShift time.Duration) (float64, float64) {
	ffmpeg := media.FindFFmpeg()
	if ffmpeg == "" {
		return 0, 0
	}
	offset, confidence, err := subs.Sync(ctx, ffmpeg, video, subtitle, 0, maxShift)
	if err != nil {
		h.Log.Info("subtitles: sync failed", "video", video, "error", err)
		return 0, 0
	}
	return offset, confidence
}

// SetKey is POST /Subtitles/Key.
func (h SubtitleHandler) SetKey(w http.ResponseWriter, r *http.Request) {
	var body struct{ Key string }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	if err := subs.WriteKey(h.DataDir, body.Key); err != nil {
		h.Log.Error("subtitles: could not store key", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not store the key"})
		return
	}
	h.Log.Info("subtitles: provider key stored", "cleared", body.Key == "")
	w.WriteHeader(http.StatusNoContent)
}

// Status is GET /Subtitles/Status — whether this server can search at all.
func (h SubtitleHandler) Status(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"HasKey":    subs.ReadKey(h.DataDir) != "",
		"CanSync":   media.FindFFmpeg() != "",
		"MinTrust":  subs.MinConfidence,
		"MaxShiftS": subs.MaxShift.Seconds(),
	})
}

func (h SubtitleHandler) itemFor(w http.ResponseWriter, r *http.Request) (store.Item, bool) {
	id := store.NormalizeID(r.PathValue("id"))
	item, err := h.Store.ItemByID(id)
	if err != nil || item.Path == "" || item.IsFolder {
		if err != nil && !errors.Is(err, store.ErrNoItem) {
			h.Log.Error("subtitles: lookup failed", "item", id, "error", err)
		}
		http.NotFound(w, r)
		return store.Item{}, false
	}
	return item, true
}

func (h SubtitleHandler) providerID(itemID string) string {
	var value string
	h.Store.DB.QueryRow(
		`SELECT value FROM item_value WHERE item_id = ? AND kind = 'provider:Tmdb'`, itemID,
	).Scan(&value)
	return value
}

// deref reads an optional number, absent meaning zero — which every field
// here treats as "not stated" anyway.
func deref(value *int) int {
	if value == nil {
		return 0
	}
	return *value
}

// maxShiftFrom reads ?maxShift=<seconds>, the owner's setting for how far out
// a subtitle may be. Clamped: under five seconds finds nothing a person would
// notice, and past five minutes a match is likelier chance than correction.
func maxShiftFrom(r *http.Request) time.Duration {
	seconds := atoiOr(r.URL.Query().Get("maxShift"), 0)
	if seconds <= 0 {
		return subs.MaxShift
	}
	return time.Duration(min(max(seconds, 5), 300)) * time.Second
}
