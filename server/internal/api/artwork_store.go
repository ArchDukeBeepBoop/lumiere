package api

import (
	"os"
	"path/filepath"
	"strings"

	"lumiere-server/internal/safefs"
)

// store writes the bytes and points the item at them.
func (h ArtworkHandler) store(itemID, kind string, body []byte, extension string) error {
	dir := filepath.Join(h.ImageDir, "chosen")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	path := filepath.Join(dir, itemID+"-"+strings.ToLower(kind)+extension)
	// Chosen by hand, so no longer removed.
	h.Store.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = 'art:removed' AND value = ?`, itemID, kind)
	var previous string
	h.Store.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = ? AND idx = 0`, itemID, kind).Scan(&previous)
	if err := safefs.WriteFile(dir, path, body, 0o600); err != nil {
		return err
	}
	// A content hash for the tag, so the client's artwork cache — which keys on
	// the tag and never revalidates — shows the new picture immediately rather
	// than the one it already has under the same name.
	if err := h.Store.SetImage(itemID, kind, path, contentTag(body), len(body)); err != nil {
		return err
	}
	// The picture it replaces is gone at once, not left for the daily sweep:
	// a choice replaces the old one for good. Only a file this server wrote,
	// and only when nothing else still shows it.
	if previous != "" && previous != path && strings.HasPrefix(previous, h.ImageDir) {
		var others int
		h.Store.DB.QueryRow(`SELECT count(*) FROM image WHERE path = ?`, previous).Scan(&others)
		if others == 0 {
			os.Remove(previous)
		}
	}
	return nil
}
