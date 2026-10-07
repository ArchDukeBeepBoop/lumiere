package api

import (
	"context"
	"encoding/json"
	"fmt"
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
}

// MetadataProgress is what a naming pass says about itself.
type MetadataProgress struct {
	Running bool   `json:"Running"`
	Named   int    `json:"Named"`
	Missed  int    `json:"Missed"`
	Pending int    `json:"Pending"`
	Current string `json:"Current,omitempty"`
	Error   string `json:"Error,omitempty"`
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

// Status is GET /Metadata/Status.
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

func (h *MetadataHandler) Status(w http.ResponseWriter, r *http.Request) {
	h.mu.Lock()
	progress := h.progress
	h.mu.Unlock()

	progress.HasKey = metadata.ReadToken(h.DataDir) != ""
	if pending, err := h.pendingCount(); err == nil {
		progress.Pending = pending
	}
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
}

// Run is POST /Metadata/Run — name what the scanner found.
func (h *MetadataHandler) Run(w http.ResponseWriter, r *http.Request) {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no TMDB key set on the server"})
		return
	}

	_ = token
	h.Start()
	w.WriteHeader(http.StatusNoContent)
}

func (h *MetadataHandler) run(token string) {
	defer func() {
		h.mu.Lock()
		h.running = false
		h.progress.Running = false
		h.progress.Current = ""
		h.mu.Unlock()
	}()

	enricher := &metadata.Enricher{
		Store: h.Store, TMDB: metadata.NewTMDB(token),
		ImageDir: h.ImageDir, Log: h.Log,
	}
	pending, err := enricher.PendingItems(perPass)
	if err != nil {
		h.Log.Error("metadata: could not list pending", "error", err)
		h.mu.Lock()
		h.progress.Error = err.Error()
		h.mu.Unlock()
		return
	}

	ctx := context.Background()
	for _, item := range pending {
		h.mu.Lock()
		h.progress.Current = item.Name
		h.mu.Unlock()

		named, err := enricher.Enrich(ctx, item)
		if err != nil {
			// One title that will not resolve is not a pass that should stop:
			// the rest of the library is still worth naming.
			h.Log.Info("metadata: not named", "item", item.Name, "reason", err)
		}

		h.mu.Lock()
		if named {
			h.progress.Named++
		} else {
			h.progress.Missed++
		}
		h.mu.Unlock()

		time.Sleep(betweenRequests)
	}
	// Then the credits of anything matched before the pass learned to ask
	// for them — a film named by an earlier version, a show the import
	// brought without its cast.
	uncredited, err := enricher.PendingCredits(perPass)
	if err != nil {
		h.Log.Error("metadata: could not list uncredited", "error", err)
	}
	for _, item := range uncredited {
		h.mu.Lock()
		h.progress.Current = item.Name + " — cast"
		h.mu.Unlock()
		if _, err := enricher.Credit(ctx, item, item.Type == "Series"); err != nil {
			h.Log.Info("metadata: credits not fetched", "item", item.Name, "reason", err)
		}
		time.Sleep(betweenRequests)
	}

	// Then the seasons, which borrow the show's poster until they have one of
	// their own — the reason every season of a new show looks identical.
	seasons, err := enricher.PendingSeasons(perPass)
	if err != nil {
		h.Log.Error("metadata: could not list seasons", "error", err)
	}
	for _, season := range seasons {
		h.mu.Lock()
		h.progress.Current = season.Series + " — season " + fmt.Sprint(season.Number)
		h.mu.Unlock()

		got, err := enricher.EnrichSeason(ctx, season)
		if err != nil {
			h.Log.Info("metadata: no season art", "series", season.Series, "reason", err)
		}
		if got {
			h.mu.Lock()
			h.progress.Named++
			h.mu.Unlock()
		}
		time.Sleep(betweenRequests)
	}

	// Then the episode stills, batched by season: TMDB returns a whole season
	// in one response, so a season of twenty-four episodes costs one request.
	batches, err := enricher.PendingEpisodeArt(episodesPerPass)
	if err != nil {
		h.Log.Error("metadata: could not list episode art", "error", err)
	}
	for _, batch := range batches {
		h.mu.Lock()
		h.progress.Current = fmt.Sprintf("%s — season %d artwork",
			batch.SeriesName, batch.Season)
		h.mu.Unlock()

		stored, err := enricher.EnrichEpisodes(ctx, batch)
		if err != nil {
			h.Log.Info("metadata: no episode art",
				"series", batch.SeriesName, "reason", err)
		}
		h.mu.Lock()
		h.progress.Named += stored
		h.mu.Unlock()
		time.Sleep(betweenRequests)
	}

	// Then a few shows whose folders follow one of TMDB's other orders. See
	// metadata.SuggestOrders.
	if n := enricher.SuggestOrders(ctx, 10); n > 0 {
		h.Log.Info("metadata: episode orders suggested", "shows", n)
	}

	// What TMDB could not name keeps the title its file carries. See
	// store.TitleUnmatchedEpisodes.
	if titled, err := h.Store.TitleUnmatchedEpisodes(); err != nil {
		h.Log.Error("metadata: file titles failed", "error", err)
	} else if titled > 0 {
		h.Log.Info("metadata: episodes titled from their files", "count", titled)
	}

	h.Log.Info("metadata pass complete",
		"named", h.progress.Named, "missed", h.progress.Missed)

	// Whatever is still bare gets a frame. After naming, never before: a
	// poster is the better picture, and this must only fill what the
	// providers could not. See media.Frames.
	h.mu.Lock()
	h.progress.Current = "Taking frames for files with no picture"
	h.mu.Unlock()
	if _, err := media.Frames(h.Store.DB, media.FindFFmpeg(), h.ImageDir, 500, h.Log); err != nil {
		h.Log.Error("frames: pass failed", "error", err)
	}
}
