package api

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"lumiere-server/internal/store"
	"lumiere-server/internal/themeart"
)

// A theme collection is named by its theme. Identifying one as a film series
// — which happened to After the End, which became Rebuild of Evangelion —
// renames it, replaces its artwork and lets the film-series pass fill it, so
// it is refused, and undone where it already happened.

// isTheme writes a refusal and reports true for a theme collection.
func (h CollectionSuggestHandler) isTheme(w http.ResponseWriter, id string) bool {
	if h.Store.ItemValue(id, "theme") == "" {
		return false
	}
	writeJSON(w, http.StatusConflict, errorBody{
		"theme collections are named by their theme; change what is in one in Settings › Library › Theme Collections"})
	return true
}

// reclaim undoes an identify on a theme collection: the series link, the
// name and synopsis it brought, and its artwork, which is then made again.
func (h CollectionSuggestHandler) reclaim(id string, theme store.Theme) {
	if h.Store.ItemValue(id, "tmdb_collection") == "" {
		return
	}
	h.Store.SetItemValue(id, "tmdb_collection", "")
	h.Store.SetItemValue(id, "lock:name", "")
	h.Store.DB.Exec(`UPDATE item SET name = ?, sort_name = ?, overview = ? WHERE id = ?`,
		theme.Name, strings.ToLower(theme.Name), themeOverview(theme), id)
	h.Store.DB.Exec(`DELETE FROM image WHERE item_id = ? AND kind IN ('Primary', 'Backdrop')`, id)
	h.Store.SetItemValue(id, "art:theme", "")
	h.Log.Info("collections: theme collection put back after an identify", "theme", theme.Slug)
}

func themeOverview(t store.Theme) string {
	return "Films and shows about " + strings.ToLower(t.Name) + ", gathered from your libraries."
}

// themeArt designs the poster and backdrop, again whenever the members it is
// made from change — unless someone has since chosen artwork of their own.
func (h CollectionSuggestHandler) themeArt(id string, theme store.Theme, members []string) {
	dir := filepath.Join(h.DataDir, "cache", "images", "themes")
	poster := filepath.Join(dir, id+"-poster.jpg")
	backdrop := filepath.Join(dir, id+"-backdrop.jpg")
	var current string
	h.Store.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = 'Primary' LIMIT 1`, id).Scan(&current)
	made := h.Store.ItemValue(id, "art:theme")
	mosaic := h.Store.ItemValue(id, "art:mosaic") != ""
	if current != "" && current != poster && !mosaic {
		return // a poster someone picked
	}
	posters, backdrops := h.Store.ArtSources(members, 4)
	sum := sha256.Sum256([]byte(fmt.Sprint(theme.Name, len(members), posters, backdrops)))
	tag := "theme" + hex.EncodeToString(sum[:6])
	if made == tag && current == poster {
		return
	}
	os.MkdirAll(dir, 0o755)
	art := themeart.Art{Key: theme.Slug, Title: theme.Name, Count: len(members), Posters: posters, Backdrops: backdrops}
	if err := themeart.Poster(art, poster); err != nil {
		h.Log.Info("collections: theme poster not made", "theme", theme.Slug, "error", err)
		return
	}
	h.Store.DB.Exec(`DELETE FROM image WHERE item_id = ? AND kind IN ('Primary', 'Backdrop')`, id)
	h.Store.SetImage(id, "Primary", poster, tag, 0)
	if themeart.Backdrop(art, backdrop) == nil {
		h.Store.SetImage(id, "Backdrop", backdrop, tag, 0)
	}
	h.Store.SetItemValue(id, "art:mosaic", "")
	h.Store.SetItemValue(id, "art:theme", tag)
}
