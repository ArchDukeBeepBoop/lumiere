package api

import (
	"context"
	"net/http"
	"strings"
	"time"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// AutoCollections makes a collection of every film series with two or more
// films here, room by room, leaving out 3D and My Videos. It adopts a
// collection that already holds the films rather than making a second, and
// tops up the ones it made. Libraries whose lookups are off (a private one,
// unless Settings says otherwise) get their collections named from their own
// films, with nothing asked of the movie database about them.
func (h CollectionSuggestHandler) AutoCollections(ctx context.Context) (made, adopted int) {
	if !h.Store.Settings().AutoCollections {
		return 0, 0
	}
	var tmdb *metadata.TMDB
	if token := metadata.ReadToken(h.DataDir); token != "" {
		tmdb = metadata.NewTMDB(token)
	}
	rooms := h.Store.LibraryRooms(h.privateViews())
	skippedRaw, _ := h.Store.Meta(store.MetaLookupSkipped)
	skipped := map[string]bool{}
	for _, v := range strings.Split(skippedRaw, ",") {
		skipped[v] = true
	}
	quiet := func(library string) bool { return skipped[rooms.View[library]] }

	// The series of films named since the import, a batch at a time.
	if tmdb != nil {
		for _, f := range h.Store.FilmsNeedingSeries(80) {
			if quiet(h.Store.ItemLibrary(f.ID)) {
				h.Store.SetItemValue(f.ID, "tmdb_series:checked", "1")
				continue
			}
			details, err := tmdb.Movie(ctx, f.Tmdb)
			if err != nil {
				break
			}
			if details.CollectionID != "" {
				h.Store.SetItemValue(f.ID, "provider:TmdbCollection", details.CollectionID)
			} else {
				h.Store.SetItemValue(f.ID, "tmdb_series:checked", "1")
			}
		}
	}

	groups, err := h.Store.TmdbGroups()
	if err != nil {
		return 0, 0
	}
	for _, g := range groups {
		byRoom := map[bool][]string{}
		for _, m := range g.Members {
			library := h.Store.ItemLibrary(m)
			if rooms.Excluded[library] {
				continue
			}
			byRoom[rooms.Private[library]] = append(byRoom[rooms.Private[library]], m)
		}
		for private, members := range byRoom {
			if len(members) < 2 || ctx.Err() != nil {
				continue
			}
			if id := h.Store.SeriesCollectionFor(g.TmdbID, private, rooms); id != "" {
				h.Store.AddMissingLinks(id, members)
				continue
			}
			if id := h.Store.CollectionHolding(members); id != "" && rooms.Private[h.Store.ItemLibrary(id)] == private {
				if h.Store.ItemValue(id, "tmdb_collection") == "" {
					h.Store.SetItemValue(id, "tmdb_collection", g.TmdbID)
				}
				h.Store.AddMissingLinks(id, members)
				adopted++
				continue
			}
			library := ""
			if private {
				library = h.Store.ItemLibrary(members[0])
			}
			id, err := h.Store.CreateCollectionIn(g.FirstName+" Collection", library, members)
			if err != nil {
				continue
			}
			h.Store.SetItemValue(id, "tmdb_collection", g.TmdbID)
			h.Store.SetItemValue(id, "auto:collection", "1")
			if tmdb != nil && !quiet(h.Store.ItemLibrary(members[0])) {
				h.dress(ctx, tmdb, id, g.TmdbID)
			}
			made++
		}
	}
	if made+adopted > 0 {
		h.Log.Info("collections: found automatically", "made", made, "adopted", adopted)
	}
	return made, adopted
}

// Auto is POST /Lumiere/Collections/Auto: the automatic pass, now.
func (h CollectionSuggestHandler) Auto(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	made, adopted := h.AutoCollections(ctx)
	writeJSON(w, http.StatusOK, map[string]int{"Made": made, "Adopted": adopted})
}
