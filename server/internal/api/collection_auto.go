package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// Collections as legitimate collections: named, described and pictured from
// the movie database's own film series, found automatically in every library
// but 3D and My Videos, room by room — a private library's collections live
// in it, and so in its room.

// dress names a collection after its film series and gives it the series'
// synopsis, poster and backdrop. A name set by hand (lock:name) is kept.
func (h CollectionSuggestHandler) dress(ctx context.Context, tmdb *metadata.TMDB, id, series string) {
	info, err := tmdb.Collection(ctx, series)
	if err != nil {
		h.Log.Info("collections: series not read", "tmdb", series, "error", err)
		return
	}
	if info.Name != "" && h.Store.ItemValue(id, "lock:name") == "" {
		h.Store.DB.Exec(`UPDATE item SET name = ?, sort_name = ? WHERE id = ?`, info.Name, info.Name, id)
	}
	if info.Overview != "" {
		h.Store.DB.Exec(`UPDATE item SET overview = ? WHERE id = ?`, info.Overview, id)
	}
	e := &metadata.Enricher{Store: h.Store, TMDB: tmdb, ImageDir: h.imageDir(), Log: h.Log}
	if info.PosterPath != "" {
		e.FetchImage(id, "Primary", "w780"+info.PosterPath)
		h.Store.SetItemValue(id, "art:mosaic", "") // a real poster replaces a made one
	}
	if info.BackdropPath != "" {
		e.FetchImage(id, "Backdrop", "w1280"+info.BackdropPath)
	}
}

func (h CollectionSuggestHandler) imageDir() string { return h.DataDir + "/cache/images" }

func (h CollectionSuggestHandler) tmdb(w http.ResponseWriter) *metadata.TMDB {
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no TMDB key set on the server"})
		return nil
	}
	return metadata.NewTMDB(token)
}

// Scan is POST /Lumiere/Collections/{id}/Scan: find the collection's film
// series by itself — the one it was given, else the one most of its films
// belong to, else one named like it — then dress and fill it.
func (h CollectionSuggestHandler) Scan(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	tmdb := h.tmdb(w)
	if tmdb == nil {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
	defer cancel()
	series := h.Store.ItemValue(id, "tmdb_collection")
	if series == "" {
		series = h.majoritySeries(id)
	}
	if series == "" {
		var name string
		h.Store.DB.QueryRow(`SELECT name FROM item WHERE id = ?`, id).Scan(&name)
		series, _ = tmdb.SearchCollection(ctx, name)
	}
	if series == "" {
		writeJSON(w, http.StatusOK, map[string]any{"Found": false})
		return
	}
	h.Store.SetItemValue(id, "tmdb_collection", series)
	h.dress(ctx, tmdb, id, series)
	added := h.FillFromSeries(ctx, false)
	writeJSON(w, http.StatusOK, map[string]any{"Found": true, "Added": added})
}

func (h CollectionSuggestHandler) majoritySeries(id string) string {
	var series string
	h.Store.DB.QueryRow(`SELECT v.value FROM link l
		JOIN item_value v ON v.item_id = l.child_id AND v.kind = 'provider:TmdbCollection' AND v.value <> ''
		WHERE l.parent_id = ? GROUP BY v.value ORDER BY count(*) DESC LIMIT 1`, id).Scan(&series)
	return series
}

type discovered struct {
	TmdbId, Name, Overview, Poster string
	Parts                          int
	// The films here in the series, with the library each is in, so the app
	// can offer only what belongs to the room it is in.
	Held []heldFilm
}

type heldFilm struct{ Id, Library string }

// Discover is GET /Lumiere/Collections/Discover?Name=…: the movie database's
// collections by that name, each with how many of its films are here.
func (h CollectionSuggestHandler) Discover(w http.ResponseWriter, r *http.Request) {
	tmdb := h.tmdb(w)
	if tmdb == nil {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	matches, err := tmdb.SearchCollections(ctx, caseInsensitive(r.URL.Query())("Name"))
	if err != nil {
		writeJSON(w, http.StatusBadGateway, errorBody{"the movie database did not answer"})
		return
	}
	out := []discovered{}
	for i, m := range matches {
		if i >= 12 {
			break
		}
		d := discovered{TmdbId: m.ID, Name: m.Name, Overview: m.Overview, Poster: m.Poster, Held: []heldFilm{}}
		if info, err := tmdb.Collection(ctx, m.ID); err == nil {
			d.Parts = len(info.Parts)
			for _, p := range info.Parts {
				for _, id := range h.Store.ItemsWithTmdb(p.ID) {
					d.Held = append(d.Held, heldFilm{Id: id, Library: LibraryView(h.Store.ItemLibrary(id))})
				}
			}
		}
		out = append(out, d)
	}
	writeJSON(w, http.StatusOK, out)
}

// CreateFromSeries is POST /Lumiere/SeriesCollections/{tmdb} with
// {"ItemIds": [...], "Private": bool}: a collection of those films, dressed
// as the series. Private puts it in the films' own library, so it lives in
// the room.
func (h CollectionSuggestHandler) CreateFromSeries(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ItemIds []string
		Private bool
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil || len(body.ItemIds) == 0 {
		writeJSON(w, http.StatusBadRequest, errorBody{"expected {\"ItemIds\": [...]}"})
		return
	}
	tmdb := h.tmdb(w)
	if tmdb == nil {
		return
	}
	series := r.PathValue("tmdb")
	ctx, cancel := context.WithTimeout(r.Context(), time.Minute)
	defer cancel()
	ids := make([]string, 0, len(body.ItemIds))
	for _, id := range body.ItemIds {
		ids = append(ids, store.NormalizeID(id))
	}
	library := ""
	if body.Private {
		library = h.Store.ItemLibrary(ids[0])
	}
	id, err := h.Store.CreateCollectionIn("Collection", library, ids)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not create the collection"})
		return
	}
	h.Store.SetItemValue(id, "tmdb_collection", series)
	h.dress(ctx, tmdb, id, series)
	writeJSON(w, http.StatusOK, map[string]string{"Id": id})
}

func (h CollectionSuggestHandler) privateViews() []string {
	raw, _ := h.Store.Meta(metaPrivateLibraries)
	return strings.Split(raw, ",")
}
