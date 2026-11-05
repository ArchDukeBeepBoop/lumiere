package api

import (
	"net/http"
	"sort"
	"strings"

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
	out := h.withArtistCovers(h.wire(items))
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            out,
		TotalRecordCount: total,
		StartIndex:       q.StartIndex,
	})
}

// withArtistCovers gives an artist without a photo their newest album's id,
// so a client can show its cover in the circle instead of an empty one.
func (h ItemsHandler) withArtistCovers(out []jellyfin.BaseItem) []jellyfin.BaseItem {
	byID, byName, err := h.Store.ArtistCovers()
	if err != nil {
		h.Log.Warn("artist covers failed", "error", err)
		return out
	}
	for i := range out {
		if out[i].ImageTags["Primary"] != "" {
			continue
		}
		if id := byID[out[i].Id]; id != "" {
			out[i].AlbumId = id
		} else if id := byName[strings.ToLower(out[i].Name)]; id != "" {
			out[i].AlbumId = id
		}
	}
	return out
}

// MusicGenres is GET /MusicGenres.
//
// The genre's name is its id; see store.MusicGenres for why. Paged in memory
// because the whole answer is a few hundred short strings — a library with
// enough genres for that to matter would have more genres than albums.
//
// Each genre carries an album of it as AlbumId, picked afresh each time, for
// the picture on its card.
func (h ItemsHandler) MusicGenres(w http.ResponseWriter, r *http.Request) {
	h.genres(w, r, h.Store.MusicGenres, h.Store.GenreCovers)
}

// Genres is GET /Genres: the same answer for films and shows.
func (h ItemsHandler) Genres(w http.ResponseWriter, r *http.Request) {
	h.genres(w, r, h.Store.VideoGenres, nil)
}

func (h ItemsHandler) genres(w http.ResponseWriter, r *http.Request, list func(string) ([]string, error),
	covers func(string) (map[string]string, error)) {
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

	pictures := map[string]string{}
	if covers != nil {
		pictures, _ = covers(parent)
	}
	items := make([]jellyfin.BaseItem, 0, end-start)
	for _, name := range names[start:end] {
		items = append(items, jellyfin.BaseItem{
			Id:       name,
			Name:     name,
			Type:     "MusicGenre",
			ServerId: h.Identity.ServerID,
			IsFolder: true,
			AlbumId:  pictures[strings.ToLower(name)],
		})
	}

	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            items,
		TotalRecordCount: total,
		StartIndex:       start,
	})
}

// TopArtists is GET /Lumiere/Music/TopArtists?ParentId=&Limit=: a music
// library's artists, most played first (see store.TopArtists), for its
// Top 10 row.
func (h ItemsHandler) TopArtists(w http.ResponseWriter, r *http.Request) {
	get := caseInsensitive(r.URL.Query())
	parent := store.NormalizeID(get("ParentId"))
	limit := atoiOr(get("Limit"), 10)
	if parent == "" || limit < 1 || limit > 50 {
		writeJSON(w, http.StatusBadRequest, errorBody{"ParentId and a Limit of 1 to 50"})
		return
	}
	ids, err := h.Store.TopArtists(parent, limit)
	if err != nil {
		h.Log.Error("top artists failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	out := []jellyfin.BaseItem{}
	if len(ids) > 0 {
		items, _, err := h.Store.Items(store.Query{IDs: ids, Recursive: true})
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
			return
		}
		rank := map[string]int{}
		for i, id := range ids {
			rank[id] = i
		}
		sort.SliceStable(items, func(i, j int) bool { return rank[items[i].ID] < rank[items[j].ID] })
		out = h.withArtistCovers(h.wire(items))
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{Items: out, TotalRecordCount: len(out)})
}
