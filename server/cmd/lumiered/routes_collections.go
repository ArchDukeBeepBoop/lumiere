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
		ImageDir: filepath.Join(api.CacheRoot, "images"),
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
	authed.HandleFunc("GET /Lumiere/WatchOrder/{id}", containers.WatchOrder)
	authed.HandleFunc("PUT /Lumiere/WatchOrder/{id}", containers.SetWatchOrder)
	authed.HandleFunc("POST /Lumiere/Collections/Fill", suggest.Fill)
	authed.HandleFunc("GET /Lumiere/Collections/SeriesSearch", suggest.SeriesSearch)
	authed.HandleFunc("POST /Lumiere/Collections/{id}/Series/{tmdb}", suggest.SetSeries)
	authed.HandleFunc("POST /Lumiere/Collections/{id}/Scan", suggest.Scan)
	authed.HandleFunc("GET /Lumiere/Collections/Discover", suggest.Discover)
	authed.HandleFunc("POST /Lumiere/SeriesCollections/{tmdb}", suggest.CreateFromSeries)
	authed.HandleFunc("POST /Lumiere/Collections/Auto", suggest.Auto)
	authed.HandleFunc("GET /Lumiere/Collections/Themes", suggest.Themes)
	authed.HandleFunc("POST /Lumiere/Collections/Themes", suggest.SetThemes)
	authed.HandleFunc("POST /Lumiere/Collections/Themes/Run", suggest.RunThemes)
	// Anime franchises from AniList. See api/collection_anilist.go.
	authed.HandleFunc("GET /Lumiere/Collections/AniList", suggest.AniListStatus)
	authed.HandleFunc("POST /Lumiere/Collections/AniList", suggest.SetAniListLibraries)
	authed.HandleFunc("POST /Lumiere/Collections/AniList/Run", suggest.RunAniList)
	authed.HandleFunc("POST /Lumiere/Collections/AniList/Names", suggest.SetFranchiseNames)
	// Smart collections: rules kept current. See api/smart_collections.go.
	authed.HandleFunc("GET /Lumiere/SmartCollections", suggest.SmartList)
	authed.HandleFunc("POST /Lumiere/SmartCollections", suggest.SmartSave)
	authed.HandleFunc("POST /Lumiere/SmartCollections/Preview", suggest.SmartPreview)
	authed.HandleFunc("GET /Lumiere/SmartCollections/Ideas", suggest.SmartIdeas)
	authed.HandleFunc("GET /Lumiere/SmartCollections/Choices", suggest.SmartChoices)
	suggest.KeepFresh()
	suggest.KeepSmartFresh()
}
