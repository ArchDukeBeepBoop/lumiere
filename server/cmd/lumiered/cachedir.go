package main

import (
	"log/slog"
	"os"
	"path/filepath"

	"lumiere-server/internal/api"
	"lumiere-server/internal/config"
	"lumiere-server/internal/store"
)

// Where pictures and scrubbing previews live: the folder chosen in Lumiere
// Control (-cache), else the data folder's own.
//
// The chosen folder is usually on the media drive, which is unplugged when
// the person is out. A folder that cannot be reached is never created — under
// /Volumes that would make a fake drive on the Mac's own disk, and the real
// one would mount beside it as "Media 1" — so the server uses its own
// folder for that run, and the pictures on the drive come back with it.
//
// Choosing a different folder moves what is already kept: see
// store.RelocateCache, which copies in the background, then repoints the
// database, then clears the old folder.
func useCacheFolder(db *store.Store, cfg *config.Config, log *slog.Logger) {
	own := filepath.Join(cfg.DataDir, "cache")
	chosen := cfg.CacheDir
	if chosen == "" {
		chosen = own
	}
	reachable := chosen == own
	if !reachable {
		if info, err := os.Stat(filepath.Dir(chosen)); err == nil && info.IsDir() {
			reachable = os.MkdirAll(chosen, 0o755) == nil
		}
	}
	if !reachable {
		log.Warn("the chosen picture folder is not there (is its drive unplugged?); using the data folder for now",
			"chosen", chosen)
		cfg.CacheDir, api.CacheRoot = own, own
		return
	}
	cfg.CacheDir, api.CacheRoot = chosen, chosen
	if before := db.CacheRoot(own); before != chosen {
		go db.RelocateCache(before, chosen, log)
	}
}
