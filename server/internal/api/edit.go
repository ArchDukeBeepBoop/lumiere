package api

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"lumiere-server/internal/store"
)

// EditHandler is POST /Items/{id}: a hand-made change to an item.
//
// It did not exist. The app's Edit Metadata sheet reads the item, changes the
// edited keys and posts the whole object back — which is Jellyfin's contract —
// and the server answered 404, so every edit failed with a number and no
// sentence. See store.ApplyEdit for which keys are honoured.
type EditHandler struct {
	Store *store.Store
	Log   *slog.Logger
}

// itemBody is the subset of Jellyfin's item shape an edit can carry. Lists of
// named things arrive as either bare strings or `{Name: …}` objects depending
// on the field; both are accepted.
type itemBody struct {
	Name            *string      `json:"Name"`
	OriginalTitle   *string      `json:"OriginalTitle"`
	SortName        *string      `json:"SortName"`
	ForcedSortName  *string      `json:"ForcedSortName"`
	Overview        *string      `json:"Overview"`
	ProductionYear  *int         `json:"ProductionYear"`
	OfficialRating  *string      `json:"OfficialRating"`
	CommunityRating *float64     `json:"CommunityRating"`
	IndexNumber     *int         `json:"IndexNumber"`
	ParentIndex     *int         `json:"ParentIndexNumber"`
	Album           *string      `json:"Album"`
	AlbumArtist     *string      `json:"AlbumArtist"`
	Genres          []string     `json:"Genres"`
	Tags            []string     `json:"Tags"`
	Studios         []namedThing `json:"Studios"`
	LockedFields    []string     `json:"LockedFields"`
	LockData        *bool        `json:"LockData"`
}

type namedThing struct {
	Name string `json:"Name"`
}

func (h EditHandler) Edit(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	if itemID == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"bad item id"})
		return
	}
	var body itemBody
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"body is not an item: " + err.Error()})
		return
	}

	var exists int
	if err := h.Store.DB.QueryRow(`SELECT count(*) FROM item WHERE id = ?`, itemID).Scan(&exists); err != nil || exists == 0 {
		writeJSON(w, http.StatusNotFound, errorBody{"no such item"})
		return
	}

	edit := store.ItemEdit{
		Name: body.Name, OriginalTitle: body.OriginalTitle, Overview: body.Overview,
		ProductionYear: body.ProductionYear, OfficialRating: body.OfficialRating,
		CommunityRating: body.CommunityRating, IndexNumber: body.IndexNumber,
		ParentIndex: body.ParentIndex, Album: body.Album, AlbumArtist: body.AlbumArtist,
		Genres: body.Genres, Tags: body.Tags, LockedFields: body.LockedFields,
	}
	// A forced sort name is the one the user typed; a plain SortName is what
	// the server last computed and posted back, which is not an instruction.
	if body.ForcedSortName != nil {
		edit.SortName = body.ForcedSortName
	}
	if body.Studios != nil {
		edit.Studios = make([]string, 0, len(body.Studios))
		for _, s := range body.Studios {
			edit.Studios = append(edit.Studios, s.Name)
		}
	}
	if body.LockData != nil && *body.LockData {
		edit.LockAll = true
	}

	if err := h.Store.ApplyEdit(itemID, edit); err != nil {
		h.Log.Error("edit: could not apply", "item", itemID, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"edit failed"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
