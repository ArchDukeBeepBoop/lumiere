package api

import (
	"errors"
	"log/slog"
	"net/http"
	"sync"

	"lumiere-server/internal/scanner"
	"lumiere-server/internal/store"
)

// RefreshHandler is POST /Library/Refresh — "go and look at the disk".
//
// It used to ask the Jellyfin importer to run, which made this server a mirror:
// nothing could appear here that Jellyfin had not catalogued first, and a file
// copied in minutes ago stayed invisible for as long as Jellyfin took to notice.
// Now it runs this server's own scanner over the media roots, so a scan finds
// what is actually on the disk.
//
// The importer still exists and still runs on its timer — it carries the
// artwork, synopses and watch history that a filesystem cannot state. The
// division is now honest: the scanner answers *what exists*, the import answers
// *what it is*.
type RefreshHandler struct {
	Store *store.Store
	Log   *slog.Logger

	// One scan at a time. A second press while one runs is answered with the
	// scan already in flight, rather than two walks competing for one disk.
	mu      sync.Mutex
	running bool
}

func (h *RefreshHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	if err := h.StartScan(); err != nil {
		h.Log.Error("scan: no roots", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"no library folders to scan"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// StartScan begins a scan in the background unless one is running — the
// Scan button and the scheduled scan both come through here, so the two can
// never walk the disk at once.
func (h *RefreshHandler) StartScan() error {
	h.mu.Lock()
	if h.running {
		h.mu.Unlock()
		h.Log.Info("scan already running")
		return nil
	}
	h.running = true
	h.mu.Unlock()

	roots, err := scanner.RootsFrom(h.Store)
	if err != nil || len(roots) == 0 {
		h.mu.Lock()
		h.running = false
		h.mu.Unlock()
		if err == nil {
			err = errNoRoots
		}
		return err
	}

	// Returns at once. A scan is minutes of work; holding the request open
	// would time out on the client long before it finished, and the status
	// endpoint below is how progress is meant to be read.
	go func() {
		defer func() {
			h.mu.Lock()
			h.running = false
			h.mu.Unlock()
		}()
		scanner.Run(h.Store, roots, h.Log)
	}()
	h.Log.Info("scan started", "libraries", len(roots))
	return nil
}

var errNoRoots = errors.New("no library folders")

// Scanning says whether a scan is running now.
func (h *RefreshHandler) Scanning() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.running
}

// Status is GET /Library/Refresh/Status.
//
// Everything the panel draws: which library, how far through, and what has been
// found so far. `Running` alone was enough when this only had to be waited on;
// a progress display needs the counts, and they are the part that makes a long
// scan legible rather than a spinner.
func (h *RefreshHandler) Status(w http.ResponseWriter, r *http.Request) {
	snapshot := scanner.Snapshot()
	snapshot.RepairedAt, _ = h.Store.Meta(store.MetaRepairedAt)
	snapshot.Changed = h.Store.ChangeMarker() + "|" + snapshot.RepairedAt
	writeJSON(w, http.StatusOK, snapshot)
}
