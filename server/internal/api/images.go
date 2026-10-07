package api

import (
	"bytes"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
)

// ImagesHandler serves artwork — the one place in this server where
// performance is visible to the eye (§7.1). A home screen realises hundreds of
// tiles, and an unresized poster is ~800 KB against ~30 KB at 300px.
type ImagesHandler struct {
	Store *store.Store
	Cache *media.ImageCache
	Log   *slog.Logger
}

// imageKinds is an allowlist, because the kind lands in a database lookup and
// in a cache path. Everything Lumiere asks for is here; anything else is a 404
// rather than a query.
var imageKinds = map[string]string{
	"primary": "Primary", "backdrop": "Backdrop", "thumb": "Thumb",
	"logo": "Logo", "banner": "Banner", "art": "Art",
}

func (h ImagesHandler) Image(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	kind, known := imageKinds[strings.ToLower(r.PathValue("kind"))]
	if id == "" || !known {
		http.NotFound(w, r)
		return
	}
	idx := 0
	if raw := r.PathValue("index"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 0 {
			http.NotFound(w, r)
			return
		}
		idx = n
	}

	ref, err := h.Store.Image(id, kind, idx)
	if errors.Is(err, store.ErrNoImage) && kind == "Primary" && idx == 0 {
		// Music borrows a cover from one level away. See store.MusicCoverFor.
		ref, err = h.Store.MusicCoverFor(id)
	}
	if err != nil {
		if !errors.Is(err, store.ErrNoImage) {
			h.Log.Error("image lookup failed", "error", err, "item", id, "kind", kind)
		}
		// A missing picture is an ordinary answer: the client draws a
		// placeholder. An error page here would be a broken tile instead.
		http.NotFound(w, r)
		return
	}

	// The tag is a content address, so a variant can never change under a given
	// URL. That makes a conditional request answerable without touching the
	// file, and makes the year-long cache honest rather than optimistic.
	etag := `"` + ref.Tag + "-w" + r.URL.Query().Get("maxWidth") + `"`
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	if match := r.Header.Get("If-None-Match"); match != "" && strings.Contains(match, ref.Tag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}

	get := caseInsensitive(r.URL.Query())
	maxWidth := atoiOr(get("maxWidth"), 0)
	variant, err := h.Cache.Get(ref.Path, ref.Tag, ref.Width, maxWidth, atoiOr(get("quality"), 90))
	if err != nil {
		// The database says there is a picture and the disk disagrees — a file
		// moved or deleted behind both servers. Worth a log line, because it
		// means the metadata tree and the database have drifted.
		h.Log.Warn("image unreadable", "error", err, "item", id, "kind", kind)
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Content-Type", variant.ContentType)
	// ServeContent rather than Write: it handles conditional requests and range
	// requests, which some clients use for large backdrops.
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(variant.Bytes))
}
