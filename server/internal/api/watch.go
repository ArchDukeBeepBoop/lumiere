package api

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// WatchHandler records what was watched — the only writes this server accepts,
// and the only data in it that cannot be rebuilt from the files on disk.
type WatchHandler struct {
	Store *store.Store
	Log   *slog.Logger
}

// playingReport is the body of all three /Sessions/Playing posts.
//
// PlayMethod is deliberately not read. It is hardcoded to "DirectPlay" by the
// client whatever route was actually chosen, so inferring anything from it
// would be inferring from a constant.
type playingReport struct {
	ItemId        string `json:"ItemId"`
	MediaSourceId string `json:"MediaSourceId"`
	PositionTicks int64  `json:"PositionTicks"`
	PlaySessionId string `json:"PlaySessionId"`
	IsPaused      bool   `json:"IsPaused"`
	EventName     string `json:"EventName"`
}

// Playing handles all three posts: start, progress and stopped.
//
// One handler because they differ only in what they mean, not in what they
// carry. /Stopped is the one that matters — it fires on stop, window close and
// app quit, and the spec is blunt that if only one of the three were
// implemented it should be that one.
func (h WatchHandler) Playing(stopped bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var report playingReport
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&report); err != nil {
			// 204 even on a body that will not parse. These are fire-and-forget
			// reports the client does not read a response from, and a 400 would
			// only make it queue and replay something that can never succeed.
			h.Log.Warn("unparsable playback report", "error", err)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		id := store.NormalizeID(report.ItemId)
		if id == "" {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		if err := h.Store.RecordProgress(store.Progress{
			ItemID:        id,
			PositionTicks: report.PositionTicks,
			SessionID:     report.PlaySessionId,
			Stopped:       stopped,
		}); err != nil {
			h.Log.Error("cannot record progress", "error", err, "item", id)
			// Not 204: this is the one failure the client should retry, because
			// the position is the thing worth keeping.
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not record progress"})
			return
		}
		if stopped {
			h.Log.Info("playback stopped", "item", id,
				"position_seconds", report.PositionTicks/10_000_000)
			if h.Store.FinishIfWatched(id, report.PositionTicks) {
				h.Log.Info("marked watched: stopped past the watched point", "item", id)
			}
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// Played is POST|DELETE /UserPlayedItems/{itemId}.
//
// DELETE zeroes the position as well as the flag — that is how Lumiere resets a
// resume point, and a server that leaves the position behind makes a
// freshly-unwatched episode resume at its last second.
func (h WatchHandler) Played(played bool) http.HandlerFunc {
	return h.mutate(func(id string) error {
		return h.Store.SetPlayed(id, played)
	}, "played")
}

// Favorite is POST|DELETE /UserFavoriteItems/{itemId}.
func (h WatchHandler) Favorite(favorite bool) http.HandlerFunc {
	return h.mutate(func(id string) error {
		return h.Store.SetFavorite(id, favorite)
	}, "favorite")
}

// mutate is the shared shape of the four toggle endpoints: normalise the id,
// write, and answer with the resulting UserData.
//
// The capture shows 200 with the full object rather than 204, and Lumiere
// ignores the body — but a client that does read it gets the truth, and it
// costs one query.
func (h WatchHandler) mutate(write func(string) error, what string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := store.NormalizeID(r.PathValue("itemId"))
		if id == "" {
			http.NotFound(w, r)
			return
		}
		if err := write(id); err != nil {
			h.Log.Error("cannot set "+what, "error", err, "item", id)
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
			return
		}
		u, err := h.Store.UserDataFor(id)
		if err != nil {
			h.Log.Error("cannot read back "+what, "error", err, "item", id)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		out := jellyfin.UserItemData{
			ItemId: id, Key: id,
			Played: u.Played, PlayCount: u.PlayCount,
			PlaybackPositionTicks: u.PositionTicks, IsFavorite: u.IsFavorite,
		}
		if stamp := rfc3339(u.LastPlayed); stamp != "" {
			out.LastPlayedDate = &stamp
		}
		writeJSON(w, http.StatusOK, out)
	}
}
