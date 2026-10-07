package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// PlaybackHandler answers the negotiation and serves the bytes.
type PlaybackHandler struct {
	Store    *store.Store
	Identity Identity
	Log      *slog.Logger
}

// playbackInfoResponse is the entire contract (§6.1).
//
// ErrorCode is deliberately absent from this struct rather than nullable: the
// capture shows it missing entirely on success, not null, and Lumiere decodes
// it without ever inspecting it. Failures are reported as an HTTP status.
type playbackInfoResponse struct {
	MediaSources  []jellyfin.MediaSource `json:"MediaSources"`
	PlaySessionId string                 `json:"PlaySessionId"`
}

// PlaybackInfo is POST /Items/{id}/PlaybackInfo.
//
// Lumiere calls it once per playback, with a 4-second timeout, and falls back
// to the MediaSources cached on the item's detail record if it does not answer
// in time. That fallback is why this handler does no work beyond a lookup: the
// same object is already served by the detail endpoint, so the two must agree,
// and the cheapest way to guarantee that is to build both from one function.
func (h PlaybackHandler) PlaybackInfo(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		http.NotFound(w, r)
		return
	}

	// The body carries a DeviceProfile the size of a page, and this server has
	// no use for it: the profile exists so Jellyfin does not volunteer a
	// transcode, and a server that never volunteers one has nothing to decide.
	// It is read and discarded rather than ignored, so a malformed body is still
	// a 400 and the connection is not left with an unread request.
	var body struct {
		MediaSourceId string `json:"MediaSourceId"`
	}
	if r.Body != nil {
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body)
	}

	item, err := h.Store.ItemByID(id)
	if err != nil {
		if !errors.Is(err, store.ErrNoItem) {
			h.Log.Error("playback info lookup failed", "error", err, "item", id)
		}
		http.NotFound(w, r)
		return
	}
	if item.Path == "" || item.IsFolder {
		// Nothing to play. A 404 rather than an empty MediaSources list, because
		// an empty list would send the client into its "no playable source"
		// path with no way to say why.
		http.NotFound(w, r)
		return
	}

	streams, err := h.Store.Streams(item.ID)
	if err != nil {
		h.Log.Error("playback info streams failed", "error", err, "item", id)
		writeJSON(w, http.StatusInternalServerError, errorBody{"streams failed"})
		return
	}

	session, err := randomHex32()
	if err != nil {
		h.Log.Error("cannot mint a play session id", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"session"})
		return
	}

	h.Log.Info("playback negotiated", "item", id, "container", item.Container,
		"streams", len(streams), "session", session)

	writeJSON(w, http.StatusOK, playbackInfoResponse{
		MediaSources:  []jellyfin.MediaSource{mediaSource(item, streams)},
		PlaySessionId: session,
	})
}
