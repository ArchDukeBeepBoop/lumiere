package main

import (
	"log/slog"
	"net/http"
	"path/filepath"

	"lumiere-server/internal/api"
	"lumiere-server/internal/store"
)

// Collections and playlists. See api.ContainerHandler and
// api.CollectionSuggestHandler.
func registerContainers(authed *http.ServeMux, db *store.Store, items api.ItemsHandler, dataDir string, log *slog.Logger) {
	containers := api.ContainerHandler{
		Store: db, Items: items, Log: log,
		ImageDir: filepath.Join(dataDir, "cache", "images"),
	}
	go containers.PosterAll()
	authed.HandleFunc("POST /Collections", containers.Create("BoxSet"))
	authed.HandleFunc("POST /Collections/{id}/Items", containers.Add)
	authed.HandleFunc("DELETE /Collections/{id}/Items", containers.Remove)
	authed.HandleFunc("POST /Playlists", containers.Create("Playlist"))
	authed.HandleFunc("GET /Playlists/{id}/Items", containers.PlaylistItems)
	authed.HandleFunc("POST /Playlists/{id}/Items", containers.Add)
	authed.HandleFunc("DELETE /Playlists/{id}/Items", containers.Remove)
	authed.HandleFunc("DELETE /Items", containers.DeleteItems)
	authed.HandleFunc("GET /Persons", items.Persons)
	authed.HandleFunc("GET /Lumiere/Overview", items.Overview)
	suggest := api.CollectionSuggestHandler{Store: db, DataDir: dataDir, Log: log}
	authed.HandleFunc("GET /Lumiere/Collections/Suggestions", suggest.Suggestions)
	authed.HandleFunc("POST /Lumiere/Collections/{id}/MergeInto/{target}", containers.Merge)
	authed.HandleFunc("GET /Lumiere/Collections/NextUp", containers.SeriesNext)
	authed.HandleFunc("GET /Lumiere/Collections/NextAfter/{id}", containers.NextAfter)
	authed.HandleFunc("POST /Lumiere/Collections/Fill", suggest.Fill)
	authed.HandleFunc("GET /Lumiere/Collections/SeriesSearch", suggest.SeriesSearch)
	authed.HandleFunc("POST /Lumiere/Collections/{id}/Series/{tmdb}", suggest.SetSeries)
	authed.HandleFunc("POST /Lumiere/Collections/{id}/Scan", suggest.Scan)
	authed.HandleFunc("GET /Lumiere/Collections/Discover", suggest.Discover)
	authed.HandleFunc("POST /Lumiere/SeriesCollections/{tmdb}", suggest.CreateFromSeries)
	authed.HandleFunc("POST /Lumiere/Collections/Auto", suggest.Auto)
	suggest.KeepFresh()
}
