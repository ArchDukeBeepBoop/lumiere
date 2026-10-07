package api

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"lumiere-server/internal/media"
	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// ItemRefreshHandler is POST /Items/{id}/Refresh: one item, looked up again.
//
// The Refresh Metadata and Replace Metadata commands on every right-click menu
// called this, and it did not exist; both failed with a 404 the app had no
// sentence for. It runs the same enrichment the naming pass runs, for this
// item alone and right now, so the app's three-second wait then re-read sees
// the result.
//
// `ReplaceAllMetadata=true` discards what is there first — synopsis, year,
// rating, provider match, the "nothing found" mark — except fields the owner
// locked in an edit. `ReplaceAllImages=true` drops the artwork too. Neither
// touches the name: a title is the one field a scrape has never been trusted
// to overwrite here, and Identify is the command for changing it.
type ItemRefreshHandler struct {
	Store    *store.Store
	DataDir  string
	ImageDir string
	Log      *slog.Logger
}

func (h ItemRefreshHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	if itemID == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"bad item id"})
		return
	}
	replaceMetadata := strings.EqualFold(r.URL.Query().Get("ReplaceAllMetadata"), "true")
	replaceImages := strings.EqualFold(r.URL.Query().Get("ReplaceAllImages"), "true")

	var item metadata.Pending
	err := h.Store.DB.QueryRow(`
		SELECT id, type, name, COALESCE(production_year, 0) FROM item WHERE id = ?`, itemID,
	).Scan(&item.ID, &item.Type, &item.Name, &item.Year)
	if err != nil {
		writeJSON(w, http.StatusNotFound, errorBody{"no such item"})
		return
	}

	if replaceMetadata {
		if err := h.clearMetadata(itemID); err != nil {
			h.Log.Error("refresh: could not clear", "item", itemID, "error", err)
		}
	}
	if replaceImages {
		if _, err := h.Store.DB.Exec(`DELETE FROM image WHERE item_id = ?`, itemID); err != nil {
			h.Log.Error("refresh: could not clear images", "item", itemID, "error", err)
		}
	}
	// Always: a refresh means "try again", and the mark means "do not".
	h.Store.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = 'provider:none'`, itemID)

	token := metadata.ReadToken(h.DataDir)
	if token != "" && (item.Type == "Movie" || item.Type == "Series") {
		enricher := &metadata.Enricher{
			Store: h.Store, TMDB: metadata.NewTMDB(token),
			ImageDir: h.ImageDir, Log: h.Log,
		}
		if _, err := enricher.Enrich(context.Background(), item); err != nil {
			h.Log.Info("refresh: lookup failed", "item", itemID, "name", item.Name, "error", err)
		}
	}
	// Whatever is still bare gets a frame, the same as after a scan.
	media.Frames(h.Store.DB, media.FindFFmpeg(), h.ImageDir, 1, h.Log)
	w.WriteHeader(http.StatusNoContent)
}

// clearMetadata forgets what a scrape wrote, keeping what the owner locked.
func (h ItemRefreshHandler) clearMetadata(itemID string) error {
	tx, err := h.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if !h.Store.IsLocked(itemID, "Overview") {
		if _, err := tx.Exec(`UPDATE item SET overview = NULL WHERE id = ?`, itemID); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(
		`UPDATE item SET community_rating = NULL WHERE id = ?`, itemID); err != nil {
		return err
	}
	for _, kind := range []string{"genre", "studio"} {
		field := strings.ToUpper(kind[:1]) + kind[1:] + "s"
		if h.Store.IsLocked(itemID, field) {
			continue
		}
		if _, err := tx.Exec(
			`DELETE FROM item_value WHERE item_id = ? AND kind = ?`, itemID, kind); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(
		`DELETE FROM item_value WHERE item_id = ? AND kind LIKE 'provider:%'`, itemID); err != nil {
		return err
	}
	return tx.Commit()
}
