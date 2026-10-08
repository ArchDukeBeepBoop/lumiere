package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"path/filepath"
	"time"

	"lumiere-server/internal/api"
	"lumiere-server/internal/config"
	"lumiere-server/internal/scanner"
	"lumiere-server/internal/schedule"
	"lumiere-server/internal/store"
)

// The server's own settings and its background work. See schedule.Keeper.
//
//	GET  /Lumiere/Server            settings, preview counts, what it is doing
//	POST /Lumiere/Server            the settings, whole
//	POST /Lumiere/Server/Previews   make previews now, whatever the hour
func registerSchedule(authed *http.ServeMux, db *store.Store, cfg config.Config,
	refresh *api.RefreshHandler, log *slog.Logger) {
	api.TrickplayRoot = filepath.Join(cfg.DataDir, "cache", "trickplay")
	keeper := &schedule.Keeper{Store: db, Log: log, Scan: refresh, TrickplayRoot: api.TrickplayRoot}
	keeper.Start()

	// Media that appears is found in about a minute, rather than at the next
	// scheduled scan — which is every six hours by default, and was the only
	// thing finding it before.
	//
	// The policy lives here rather than in the watcher, which only reports that
	// the disk changed and has stopped changing. Refusing while something plays
	// keeps a scan and its naming pass off the disk mid-film; returning false
	// rather than swallowing the change means the next tick offers it again.
	watcher := &scanner.Watcher{
		Roots: func() ([]scanner.Root, error) { return scanner.RootsFrom(db) },
		Log:   log,
		OnChange: func() bool {
			if db.RecentlyPlaying(3 * time.Minute) {
				return false
			}
			if refresh.Scanning() {
				return false
			}
			if err := refresh.StartScan(); err != nil {
				log.Info("watched scan: skipped", "reason", err)
				return false
			}
			return true
		},
	}
	watcher.Start()
	api.LoadLibraryViews(db)
	api.Blocked = func(ip string) bool {
		for _, b := range db.Settings().BlockedAddresses {
			if b == ip {
				return true
			}
		}
		return false
	}

	authed.HandleFunc("GET /Videos/{id}/Trickplay/{width}/{file}", api.Trickplay)
	// Lyrics from the .lrc beside each track. See api.LyricsHandler.
	lyrics := api.LyricsHandler{Store: db}
	authed.HandleFunc("GET /Audio/{id}/Lyrics", lyrics.Get)
	authed.HandleFunc("POST /Audio/{id}/Lyrics", lyrics.Post)
	convert := api.ConvertHandler{Store: db, Log: log}
	authed.HandleFunc("GET /Videos/{id}/aac.mkv", convert.AAC)
	android := api.AndroidHandler{DataDir: cfg.DataDir, Log: log}
	authed.HandleFunc("POST /Lumiere/Diagnostics", android.Diagnostics)
	authed.HandleFunc("GET /Lumiere/Android/Latest", android.Latest)
	authed.HandleFunc("GET /Lumiere/Android/lumiere.apk", android.Package)
	// Preferences a person carries between their devices — playback, subtitles,
	// Home — kept as the app sends them; device-specific ones never come here.
	authed.HandleFunc("GET /Lumiere/ClientSettings", func(w http.ResponseWriter, r *http.Request) {
		raw, _ := db.Meta("client_settings")
		if raw == "" {
			raw = "{}"
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(raw))
	})
	authed.HandleFunc("POST /Lumiere/ClientSettings", func(w http.ResponseWriter, r *http.Request) {
		var v map[string]any
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&v); err != nil {
			http.Error(w, "expected a JSON object", http.StatusBadRequest)
			return
		}
		raw, _ := json.Marshal(v)
		if err := db.SetMeta("client_settings", string(raw)); err != nil {
			http.Error(w, "could not save", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	authed.HandleFunc("GET /Lumiere/Server", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, keeper.Status())
	})
	authed.HandleFunc("POST /Lumiere/Server", func(w http.ResponseWriter, r *http.Request) {
		v := db.Settings()
		if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
			http.Error(w, "expected the settings as JSON", http.StatusBadRequest)
			return
		}
		before := db.Settings().ListensOnNetwork
		if _, err := db.SetSettings(v); err != nil {
			http.Error(w, "could not save", http.StatusInternalServerError)
			return
		}
		if v.ListensOnNetwork != before && api.NetworkOnChange != nil {
			api.NetworkOnChange(v.ListensOnNetwork)
		}
		writeJSON(w, keeper.Status())
	})
	authed.HandleFunc("POST /Lumiere/Server/Previews", func(w http.ResponseWriter, r *http.Request) {
		keeper.PreviewsNow()
		w.WriteHeader(http.StatusNoContent)
	})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

// startNetwork serves the home network too, when Settings says so. See
// api.Network.
func startNetwork(handler http.Handler, cfg config.Config, db *store.Store, identity api.Identity, log *slog.Logger) {
	_, port, _ := net.SplitHostPort(cfg.Addr)
	n := &api.Network{Handler: handler, Identity: identity, Log: log}
	fmt.Sscan(port, &n.Port)
	api.NetworkOnChange = n.Apply
	n.Apply(db.Settings().ListensOnNetwork)
	go n.Watch(context.Background(), 20*time.Second)
}
