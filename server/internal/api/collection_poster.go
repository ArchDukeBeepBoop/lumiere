package api

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"

	"lumiere-server/internal/mosaic"
)

// refreshPoster remakes a collection's poster from its first four members,
// unless someone chose its artwork — a poster that was picked or imported is
// never replaced. The tag follows the members, so a client's cached copy is
// replaced when they change.
func (h ContainerHandler) refreshPoster(id string) {
	if h.ImageDir == "" {
		return
	}
	ours, posters := h.Store.CollectionPosters(id)
	if !ours || len(posters) == 0 {
		return
	}
	sum := sha256.Sum256([]byte(strings.Join(posters, "\n")))
	tag := "mosaic" + hex.EncodeToString(sum[:6])
	os.MkdirAll(h.ImageDir, 0o755)
	out := filepath.Join(h.ImageDir, id+"-mosaic.jpg")
	if err := mosaic.Compose(posters, out); err != nil {
		h.Log.Info("collections: no poster made", "id", id, "error", err)
		return
	}
	h.Store.SetImage(id, "Primary", out, tag, 0)
	h.Store.SetItemValue(id, "art:mosaic", "1")
	h.Log.Info("collections: poster made from members", "id", id, "posters", len(posters))
}

// PosterAll gives every collection that has no poster one, at startup.
func (h ContainerHandler) PosterAll() {
	for _, id := range h.Store.PosterlessCollections() {
		h.refreshPoster(id)
	}
}
