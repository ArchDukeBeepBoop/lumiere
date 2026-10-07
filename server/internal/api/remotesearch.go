package api

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// RemoteSearchHandler is POST /Items/RemoteSearch/{Movie|Series}: the
// Identify sheet asking the server's own provider for candidates.
//
// Missing until now, so identifying through "your server's providers" failed
// with a 404 while the app's own TMDB key worked — two paths to one result,
// one of them dead. This answers in Jellyfin's shape, from TMDB, with the key
// the server holds; the app then posts the chosen result to RemoteSearch/Apply,
// which already existed.
type RemoteSearchHandler struct {
	Store   *store.Store
	DataDir string
	Log     *slog.Logger
}

type remoteSearchQuery struct {
	SearchInfo struct {
		Name   string `json:"Name"`
		Year   int    `json:"Year"`
		ItemId string `json:"ItemId"`
	} `json:"SearchInfo"`
}

type remoteSearchResult struct {
	Name               string            `json:"Name"`
	ProductionYear     *int              `json:"ProductionYear,omitempty"`
	Overview           string            `json:"Overview,omitempty"`
	ImageUrl           string            `json:"ImageUrl,omitempty"`
	SearchProviderName string            `json:"SearchProviderName"`
	ProviderIds        map[string]string `json:"ProviderIds"`
}

func (h RemoteSearchHandler) Search(series bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var query remoteSearchQuery
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&query); err != nil {
			writeJSON(w, http.StatusBadRequest, errorBody{"bad search: " + err.Error()})
			return
		}
		token := metadata.ReadToken(h.DataDir)
		if token == "" || query.SearchInfo.Name == "" {
			// No key is not an error the sheet can act on; an empty list is
			// what "your server's providers found nothing" is written for.
			writeJSON(w, http.StatusOK, []remoteSearchResult{})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		defer cancel()
		tmdb := metadata.NewTMDB(token)
		var candidates []metadata.Candidate
		var err error
		if series {
			candidates, err = tmdb.SearchSeries(ctx, query.SearchInfo.Name, query.SearchInfo.Year)
		} else {
			candidates, err = tmdb.SearchMovie(ctx, query.SearchInfo.Name, query.SearchInfo.Year)
		}
		if err != nil {
			h.Log.Info("remote search failed", "name", query.SearchInfo.Name, "error", err)
			writeJSON(w, http.StatusBadGateway, errorBody{"the provider did not answer"})
			return
		}

		out := make([]remoteSearchResult, 0, len(candidates))
		for _, c := range candidates {
			result := remoteSearchResult{
				Name: c.Title, Overview: c.Overview,
				SearchProviderName: "TheMovieDb",
				ProviderIds:        map[string]string{"Tmdb": c.ID},
			}
			if c.Year > 0 {
				year := c.Year
				result.ProductionYear = &year
			}
			if c.Poster != "" {
				result.ImageUrl = metadata.ImageBase + c.Poster
			}
			out = append(out, result)
		}
		writeJSON(w, http.StatusOK, out)
	}
}
