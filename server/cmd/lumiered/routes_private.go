package main

import (
	"net/http"

	"lumiere-server/internal/api"
	"lumiere-server/internal/store"
)

// The apps' privacy settings: always answered, since the phone and projector
// cannot tell private from ordinary without them.
func registerPrivate(authed *http.ServeMux, db *store.Store) {
	h := api.PrivateHandler{Store: db}
	authed.HandleFunc("GET /Lumiere/Private", h.PrivateLibraries)
	authed.HandleFunc("POST /Lumiere/Private", h.SetPrivateLibraries)
	authed.HandleFunc("POST /Lumiere/Metadata/Skip", h.SkipLookups)
}
