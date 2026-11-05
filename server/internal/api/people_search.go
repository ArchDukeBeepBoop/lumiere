package api

import (
	"net/http"
	"strconv"
	"strings"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// Persons is GET /Persons?searchTerm= — people by name, in Jellyfin's
// envelope, so search can offer a person ahead of their titles.
func (h ItemsHandler) Persons(w http.ResponseWriter, r *http.Request) {
	get := caseInsensitive(r.URL.Query())
	// ?IsFavorite=true: the people starred, for Favourites' Cast & Crew.
	search := func() ([]store.PersonMatch, error) {
		return h.Store.SearchPeople(get("searchTerm"), atoiOr(get("Limit"), 8))
	}
	if strings.EqualFold(get("IsFavorite"), "true") {
		search = h.Store.FavoritePeople
	}
	people, err := search()
	if err != nil {
		h.Log.Error("person search failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	items := make([]jellyfin.BaseItem, 0, len(people))
	for _, p := range people {
		items = append(items, jellyfin.BaseItem{
			Id: p.ID, Name: p.Name, Type: "Person", Overview: strconv.Itoa(p.Credits) + " titles",
		})
		if p.Tag != "" {
			items[len(items)-1].ImageTags = map[string]string{"Primary": p.Tag}
		}
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{Items: items, TotalRecordCount: len(items)})
}

// Overview is GET /Lumiere/Overview — the library in a few numbers.
func (h ItemsHandler) Overview(w http.ResponseWriter, r *http.Request) {
	o, err := h.Store.LibraryOverview()
	if err != nil {
		h.Log.Error("overview failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, o)
}
