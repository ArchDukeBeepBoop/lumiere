package api

import (
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// Artists is GET /Artists.
//
// Its own endpoint because that is the only place Jellyfin serves them: artists
// are derived from track tags rather than filed as children, so a client asking
// /Items for them gets nothing and knows to come here instead. Here they *are*
// ordinary rows, so this is /Items with the type fixed — but the route has to
// exist or the client's Artists tab is permanently empty, which is what it was.
func (h ItemsHandler) Artists(w http.ResponseWriter, r *http.Request) {
	q := queryFrom(r.URL.Query())
	q.Types = []string{"MusicArtist"}
	q.Recursive = true
	q.OneArtistPerName = true
	if len(q.SortBy) == 0 {
		q.SortBy = []string{"SortName"}
	}

	items, total, err := h.Store.Items(q)
	if err != nil {
		h.Log.Error("artists query failed", "error", err, "query", r.URL.RawQuery)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            h.wire(items),
		TotalRecordCount: total,
		StartIndex:       q.StartIndex,
	})
}

// MusicGenres is GET /MusicGenres.
//
// The genre's name is its id; see store.MusicGenres for why. Paged in memory
// because the whole answer is a few hundred short strings — a library with
// enough genres for that to matter would have more genres than albums.
func (h ItemsHandler) MusicGenres(w http.ResponseWriter, r *http.Request) {
	h.genres(w, r, h.Store.MusicGenres)
}

// Genres is GET /Genres: the same answer for films and shows.
func (h ItemsHandler) Genres(w http.ResponseWriter, r *http.Request) {
	h.genres(w, r, h.Store.VideoGenres)
}

func (h ItemsHandler) genres(w http.ResponseWriter, r *http.Request, list func(string) ([]string, error)) {
	get := caseInsensitive(r.URL.Query())
	parent := store.NormalizeID(get("ParentId"))

	names, err := list(parent)
	if err != nil {
		h.Log.Error("genres query failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}

	total := len(names)
	start := atoiOr(get("StartIndex"), 0)
	if start > total {
		start = total
	}
	end := total
	if limit := atoiOr(get("Limit"), 0); limit > 0 && start+limit < end {
		end = start + limit
	}

	items := make([]jellyfin.BaseItem, 0, end-start)
	for _, name := range names[start:end] {
		items = append(items, jellyfin.BaseItem{
			Id:       name,
			Name:     name,
			Type:     "MusicGenre",
			ServerId: h.Identity.ServerID,
			IsFolder: true,
		})
	}

	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            items,
		TotalRecordCount: total,
		StartIndex:       start,
	})
}
