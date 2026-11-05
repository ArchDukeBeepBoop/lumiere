package api

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// AniListStatus is GET /Lumiere/Collections/AniList: which libraries are
// looked up, how far the lookups have got, and how many franchises there are.
func (h CollectionSuggestHandler) AniListStatus(w http.ResponseWriter, r *http.Request) {
	type library struct {
		Id, Name string
		On       bool
	}
	_, on := h.Store.AniListLibraries(h.privateViews())
	isOn := map[string]bool{}
	for _, v := range on {
		isOn[v] = true
	}
	libs, _ := h.Store.ListLibraries()
	var out []library
	for _, l := range libs {
		if l.Kind == "tvshows" || l.Kind == "movies" || l.Kind == "" {
			out = append(out, library{l.ID, l.Name, isOn[l.ID]})
		}
	}
	var checked, matched, franchises int
	h.Store.DB.QueryRow(`SELECT count(*) FROM item_value WHERE kind = 'anilist:checked'`).Scan(&checked)
	h.Store.DB.QueryRow(`SELECT count(*) FROM item_value WHERE kind = 'provider:AniList'`).Scan(&matched)
	h.Store.DB.QueryRow(`SELECT count(*) FROM item_value v JOIN item b ON b.id = v.item_id
		WHERE v.kind = 'anilist:franchise'`).Scan(&franchises)
	running := !anilistRunning.TryLock()
	if !running {
		anilistRunning.Unlock()
	}
	writeJSON(w, http.StatusOK, map[string]any{"Libraries": out, "Checked": checked,
		"Matched": matched, "Franchises": franchises, "Running": running, "Art": h.Store.AniListArtOn()})
}

// SetAniListLibraries is POST /Lumiere/Collections/AniList {"Libraries": [ids],
// "Art": bool}. An empty list turns lookups off; the default returns only by
// clearing it in the database, which no button does. Art, when sent, chooses
// AniList's key art (true) or the four-poster mosaic (false).
func (h CollectionSuggestHandler) SetAniListLibraries(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Libraries []string
		Art       *bool
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 16<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	if body.Art != nil {
		art := "on"
		if !*body.Art {
			art = "off"
		}
		h.Store.SetMeta(store.MetaAniListArt, art)
	}
	value := strings.Join(body.Libraries, ",")
	if value == "" {
		value = "none"
	}
	h.Store.SetMeta(store.MetaAniListLibraries, value)
	h.RunAniList(w, r)
}

// SetFranchiseNames is POST /Lumiere/Collections/AniList/Names
// {"Names": {"<library>": "folder"|"romaji"}}: how each library wants its
// franchises named, sent by the app when its Title Order changes. A pass
// follows, which renames what is already there (unless named by hand).
func (h CollectionSuggestHandler) SetFranchiseNames(w http.ResponseWriter, r *http.Request) {
	var body struct{ Names map[string]string }
	if err := json.NewDecoder(io.LimitReader(r.Body, 16<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	h.Store.SetFranchiseNaming(body.Names)
	h.RunAniList(w, r)
}

// RunAniList is POST /Lumiere/Collections/AniList/Run: a pass in the
// background, answered at once — the first one can take a while.
func (h CollectionSuggestHandler) RunAniList(w http.ResponseWriter, r *http.Request) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Minute)
		defer cancel()
		h.AniListFranchises(ctx, 4000)
	}()
	w.WriteHeader(http.StatusAccepted)
}
