package main

import (
	"net/http"

	"lumiere-server/internal/api"
)

// Music's own routes: artists and genres, which are not rows /Items lists,
// and a library's Top 10 artists.
func registerMusic(authed *http.ServeMux, items api.ItemsHandler) {
	authed.HandleFunc("GET /Artists", items.Artists)
	authed.HandleFunc("GET /Artists/AlbumArtists", items.Artists)
	authed.HandleFunc("GET /MusicGenres", items.MusicGenres)
	authed.HandleFunc("GET /Lumiere/Music/TopArtists", items.TopArtists)
}

// Changing an item's pictures: from a file, removed, or copied from another
// item — a collection taking one of its own titles' posters.
func registerArtworkEdits(authed *http.ServeMux, artwork api.ArtworkHandler) {
	authed.HandleFunc("POST /Items/{id}/Images/{kind}", artwork.Upload)
	authed.HandleFunc("DELETE /Items/{id}/Images/{kind}", artwork.Delete)
	authed.HandleFunc("POST /Lumiere/Items/{id}/Images/{kind}/From/{source}", artwork.CopyFrom)
}
