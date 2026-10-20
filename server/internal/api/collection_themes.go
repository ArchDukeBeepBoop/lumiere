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

// minThemeSize: a theme with two titles is a coincidence, not a shelf.
const minThemeSize = 3

// ThemeCollections builds a collection for every theme that is on, room by
// room, leaving out 3D and My Videos, and keeps each one's members in step
// with the library. A theme turned off loses its collections. Titles with
// no keywords yet are asked about first, a batch a day, unless their
// library's lookups are off.
func (h CollectionSuggestHandler) ThemeCollections(ctx context.Context) (made, changed int) {
	rooms := h.Store.LibraryRooms(h.privateViews())
	if token := metadata.ReadToken(h.DataDir); token != "" {
		tmdb := metadata.NewTMDB(token)
		skippedRaw, _ := h.Store.Meta(store.MetaLookupSkipped)
		for _, t := range h.Store.UntaggedTitles(120) {
			if ctx.Err() != nil {
				break
			}
			if strings.Contains(","+skippedRaw+",", ","+rooms.View[h.Store.ItemLibrary(t[0])]+",") {
				h.Store.SetItemValue(t[0], "keywords:checked", "1")
				continue
			}
			words, err := tmdb.Keywords(ctx, t[1] == "Series", t[2])
			if err != nil {
				break
			}
			h.Store.AddTags(t[0], words)
			h.Store.SetItemValue(t[0], "keywords:checked", "1")
		}
	}
	for _, theme := range h.Store.Themes() {
		if !theme.Enabled {
			for _, id := range h.Store.ThemeCollections(theme.Slug) {
				h.Store.DeleteContainer(id)
			}
			continue
		}
		byRoom := map[bool][]string{false: nil, true: nil}
		for _, m := range h.Store.ThemeMembers(theme) {
			library := h.Store.ItemLibrary(m)
			if rooms.Excluded[library] {
				continue
			}
			byRoom[rooms.Private[library]] = append(byRoom[rooms.Private[library]], m)
		}
		for private, members := range byRoom {
			existing := h.Store.ThemeCollectionFor(theme.Slug, private, rooms)
			if len(members) < minThemeSize {
				if existing != "" {
					h.Store.DeleteContainer(existing)
				}
				continue
			}
			if existing != "" {
				h.reclaim(existing, theme)
				if a, r := h.Store.SyncLinks(existing, members); a+r > 0 {
					changed++
				}
				h.themeArt(existing, theme, members)
				continue
			}
			library := ""
			if private {
				library = h.Store.ItemLibrary(members[0])
			}
			id, err := h.Store.CreateCollectionIn(theme.Name, library, members)
			if err != nil {
				continue
			}
			h.Store.SetItemValue(id, "theme", theme.Slug)
			h.Store.SetItemValue(id, "auto:collection", "1")
			h.Store.DB.Exec(`UPDATE item SET overview = ? WHERE id = ?`, themeOverview(theme), id)
			h.themeArt(id, theme, members)
			made++
		}
	}
	if made+changed > 0 {
		h.Log.Info("collections: themes", "made", made, "changed", changed)
	}
	return made, changed
}

// themeView is a theme with how many titles it finds.
type themeView struct {
	store.Theme
	Count int `json:"Count"`
}

// Themes is GET /Lumiere/Collections/Themes.
func (h CollectionSuggestHandler) Themes(w http.ResponseWriter, r *http.Request) {
	out := []themeView{}
	for _, t := range h.Store.Themes() {
		out = append(out, themeView{t, len(h.Store.ThemeMembers(t))})
	}
	writeJSON(w, http.StatusOK, map[string]any{"Themes": out})
}

// SetThemes is POST /Lumiere/Collections/Themes {"Themes": [...]}: the whole
// list, built-in and custom, then a pass so the change shows at once.
func (h CollectionSuggestHandler) SetThemes(w http.ResponseWriter, r *http.Request) {
	var body struct{ Themes []store.Theme }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"expected {\"Themes\": [...]}"})
		return
	}
	for i := range body.Themes {
		t := &body.Themes[i]
		if t.Slug == "" {
			t.Slug = "custom-" + strings.ToLower(strings.Join(strings.Fields(t.Name), "-"))
			t.Custom = true
		}
	}
	if err := h.Store.SaveThemes(body.Themes); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
		return
	}
	h.RunThemes(w, r)
}

// RunThemes is POST /Lumiere/Collections/Themes/Run.
func (h CollectionSuggestHandler) RunThemes(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	made, changed := h.ThemeCollections(ctx)
	writeJSON(w, http.StatusOK, map[string]int{"Made": made, "Changed": changed})
}
