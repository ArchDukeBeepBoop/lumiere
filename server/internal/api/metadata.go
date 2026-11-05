package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// MetadataHandler runs the server's own naming pass.
//
// The last thing this server needed Jellyfin for. The scanner finds the files;
// this says what they are — synopsis, year, rating, genres, studio, artwork —
// from TMDB, with a key this server holds.
//
// That is a deliberate departure from identify and the episode-image fetcher,
// which keep the key in Lumiere and have the server write down what it is told.
// Those were right when the server was a mirror of Jellyfin. A server that
// catalogues its own disk has to be able to name what it found with no app
// open, and a credential it cannot read is a credential it cannot use.
type MetadataHandler struct {
	Store    *store.Store
	DataDir  string
	ImageDir string
	Log      *slog.Logger

	mu       sync.Mutex
	running  bool
	progress MetadataProgress
	// rejected is the key TMDB last refused, so the automatic pass does not
	// ask again with it every five minutes. See metadata_auto.go.
	rejected string
}

// MetadataProgress is what a naming pass says about itself.
type MetadataProgress struct {
	Running bool `json:"Running"`
	Named   int  `json:"Named"`
	Missed  int  `json:"Missed"`
	Pending int  `json:"Pending"`
	// Unmatched is every film and show with no provider id — what
	// "identify everything" would ask about. See metadata.UnmatchedClause.
	Unmatched int    `json:"Unmatched"`
	Current   string `json:"Current,omitempty"`
	Error     string `json:"Error,omitempty"`
	// HasKey says whether a pass can run at all, so the client can offer the
	// field rather than a button that fails.
	HasKey bool `json:"HasKey"`
}

// betweenRequests is the pause between lookups.
//
// TMDB's published limit is generous, but a library with a thousand unnamed
// folders is a thousand requests and there is no hurry: this runs in the
// background, and being a good guest costs nothing anyone is waiting on.
const betweenRequests = 250 * time.Millisecond

// perPass caps one run. Bounded so a pass ends, reports, and can be run again —
// an unbounded loop over a large library is a background task nobody can see
// the end of.
const perPass = 200

// episodesPerPass caps the episode rows one pass considers.
//
// Higher than the title cap because these collapse: 4,000 episodes are a few
// hundred seasons, and a season is one request. The cap is on rows read, not on
// requests made.
const episodesPerPass = 4000

// Start runs a naming pass if one is not already going.
//
// Exported so the scanner can call it directly when a pass finds new files —
// see scanner.AfterScan. Returns whether it started: a key that is not set, or
// a pass already running, are both ordinary and neither is an error.
func (h *MetadataHandler) Start() bool {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		return false
	}

	h.mu.Lock()
	if h.running {
		h.mu.Unlock()
		return false
	}
	h.running = true
	h.progress = MetadataProgress{Running: true}
	h.mu.Unlock()

	go h.run(token)
	return true
}

// FramesOnly runs the frame pass by itself, for a scan on a server with no
// provider key: naming cannot happen, but a bare file can still get a picture.
func (h *MetadataHandler) FramesOnly() {
	h.mu.Lock()
	if h.running {
		h.mu.Unlock()
		return
	}
	h.running = true
	h.mu.Unlock()
	go func() {
		defer func() {
			h.mu.Lock()
			h.running = false
			h.mu.Unlock()
		}()
		if _, err := media.Frames(h.Store.DB, media.FindFFmpeg(), h.ImageDir, 500, h.Log); err != nil {
			h.Log.Error("frames: pass failed", "error", err)
		}
	}()
}

// Status is GET /Metadata/Status.
func (h *MetadataHandler) Status(w http.ResponseWriter, r *http.Request) {
	h.mu.Lock()
	progress := h.progress
	h.mu.Unlock()

	progress.HasKey = metadata.ReadToken(h.DataDir) != ""
	if pending, err := h.pendingCount(); err == nil {
		progress.Pending = pending
	}
	h.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE ` + metadata.UnmatchedClause).Scan(&progress.Unmatched)
	writeJSON(w, http.StatusOK, progress)
}

// SetKey is POST /Metadata/Key — the provider credential, set once.
//
// Localhost only, like everything else here, and stored 0600 beside the
// database. An empty body clears it, which is how a key is removed.
func (h *MetadataHandler) SetKey(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Token string `json:"Token"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 8<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	if err := metadata.WriteToken(h.DataDir, body.Token); err != nil {
		h.Log.Error("metadata: could not store key", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not store the key"})
		return
	}
	h.Log.Info("metadata: provider key stored", "cleared", body.Token == "")
	w.WriteHeader(http.StatusNoContent)
	h.Start() // a new key is a reason to look now, not in five minutes
}

// Run is POST /Metadata/Run — name what the scanner found.
func (h *MetadataHandler) Run(w http.ResponseWriter, r *http.Request) {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no TMDB key set on the server"})
		return
	}

	_ = token
	if r.URL.Query().Get("scope") == "all" {
		// Kept in the database rather than in memory, so a pass paused for
		// playback or a restart picks the request up again. See IdentifyAllKey.
		if err := h.Store.SetMeta(IdentifyAllKey, time.Now().UTC().Format(time.RFC3339)); err != nil {
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not record the request"})
			return
		}
	}
	h.Start()
	w.WriteHeader(http.StatusNoContent)
}
