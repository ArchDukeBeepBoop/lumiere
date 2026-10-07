package api

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"lumiere-server/internal/metadata"
	"lumiere-server/internal/store"
)

// ArtworkHandler is choosing, replacing and removing an item's picture.
//
// Four endpoints Lumiere has always called and this server never answered: the
// menu offered "Choose Artwork…" and the request 404'd, so the sheet opened
// empty and nothing anyone picked was ever applied. Removing was worse — a 405,
// which the client had no reason to treat differently from a refusal.
//
// They are answerable now because the server holds a provider key of its own.
// Before that there was nothing to list.
type ArtworkHandler struct {
	Store    *store.Store
	DataDir  string
	ImageDir string
	Log      *slog.Logger
}

// Remote is GET /Items/{id}/RemoteImages.
//
// What a provider has for this title. Empty rather than an error where the item
// was never matched or no key is set: the sheet then says it found nothing,
// which is true, instead of showing a failure for a library that simply has no
// provider behind it.
func (h ArtworkHandler) Remote(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	wanted := caseInsensitive(r.URL.Query())("type")
	if wanted == "" {
		wanted = "Primary"
	}

	empty := map[string]any{"Images": []any{}, "TotalRecordCount": 0}
	token := metadata.ReadToken(h.DataDir)
	if itemID == "" || token == "" {
		writeJSON(w, http.StatusOK, empty)
		return
	}

	tmdbID, err := h.Store.ProviderID(itemID, "Tmdb")
	if err != nil || tmdbID == "" {
		writeJSON(w, http.StatusOK, empty)
		return
	}

	item, err := h.Store.ItemByID(itemID)
	if err != nil {
		writeJSON(w, http.StatusOK, empty)
		return
	}
	kind := "movie"
	if item.Type == "Series" || item.Type == "Season" || item.Type == "Episode" {
		kind = "tv"
	}

	images, err := metadata.NewTMDB(token).Images(r.Context(), kind, tmdbID)
	if err != nil {
		h.Log.Info("artwork: provider lookup failed", "item", itemID, "error", err)
		writeJSON(w, http.StatusOK, empty)
		return
	}

	// Jellyfin's shape, because that is what the client decodes.
	type wire struct {
		ProviderName    string  `json:"ProviderName"`
		Url             string  `json:"Url"`
		ThumbnailUrl    string  `json:"ThumbnailUrl"`
		Type            string  `json:"Type"`
		Width           int     `json:"Width"`
		Height          int     `json:"Height"`
		Language        string  `json:"Language,omitempty"`
		CommunityRating float64 `json:"CommunityRating,omitempty"`
	}
	out := []wire{}
	for _, image := range images {
		if !strings.EqualFold(image.Kind, wanted) {
			continue
		}
		out = append(out, wire{
			ProviderName: "TheMovieDb", Url: image.URL, ThumbnailUrl: image.Thumb,
			Type: image.Kind, Width: image.Width, Height: image.Height,
			Language: image.Language, CommunityRating: image.Rating,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"Images": out, "TotalRecordCount": len(out),
	})
}

// Download is POST /Items/{id}/RemoteImages/Download — apply a chosen picture.
func (h ArtworkHandler) Download(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	get := caseInsensitive(r.URL.Query())
	raw, kind := get("imageurl"), get("type")
	if kind == "" {
		kind = "Primary"
	}
	if itemID == "" || raw == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"no image named"})
		return
	}

	// The same allowlist and redirect policy identify uses. This URL arrives in
	// a request, and a picker is exactly where one could arrive from anywhere.
	if err := h.fetch(r.Context(), itemID, kind, raw); err != nil {
		h.Log.Info("artwork: not applied", "item", itemID, "reason", err)
		writeJSON(w, http.StatusBadRequest, errorBody{err.Error()})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Upload is POST /Items/{id}/Images/{kind} — a file from the user's own Mac.
//
// The body is base64, not raw bytes, with the real image type in Content-Type.
// That is Jellyfin's documented quirk and every client follows it; matching it
// is what lets Lumiere's existing upload path work unchanged.
func (h ArtworkHandler) Upload(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	kind := imageKind(r.PathValue("kind"))
	if itemID == "" || kind == "" {
		http.NotFound(w, r)
		return
	}

	encoded, err := io.ReadAll(io.LimitReader(r.Body, 32<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	body, err := base64.StdEncoding.DecodeString(string(encoded))
	if err != nil {
		// Some clients send raw bytes. Accepting both is cheaper than being
		// right about which one this was.
		body = encoded
	}

	// From the bytes, not the header. A poster saved from a browser is a
	// WebP more often than not, whatever its name says, and the file was
	// being written as .jpg with WebP inside.
	extension := sniffExtension(body, r.Header.Get("Content-Type"))
	if err := h.store(itemID, kind, body, extension); err != nil {
		h.Log.Error("artwork: upload failed", "item", itemID, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not store the image"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Delete is DELETE /Items/{id}/Images/{kind} — remove it entirely.
//
// The row goes, and so does the file where this server fetched it. A wrong
// poster you overwrite is still there; a wrong poster you delete is gone, and
// the difference is the whole reason the client offers both.
func (h ArtworkHandler) Delete(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("id"))
	kind := imageKind(r.PathValue("kind"))
	if itemID == "" || kind == "" {
		http.NotFound(w, r)
		return
	}

	var path string
	_ = h.Store.DB.QueryRow(
		`SELECT path FROM image WHERE item_id = ? AND kind = ?`, itemID, kind,
	).Scan(&path)

	if _, err := h.Store.DB.Exec(
		`DELETE FROM image WHERE item_id = ? AND kind = ?`, itemID, kind,
	); err != nil {
		h.Log.Error("artwork: delete failed", "item", itemID, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not remove it"})
		return
	}

	// Only files this server wrote. Jellyfin's metadata tree is not ours to
	// delete from — the row is what this server controls, and removing the
	// source file would damage a library Jellyfin still manages.
	if path != "" && strings.HasPrefix(path, h.ImageDir) {
		_ = os.Remove(path)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h ArtworkHandler) fetch(ctx context.Context, itemID, kind, raw string) error {
	u, err := allowedArtworkURL(raw)
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return err
	}

	client := &http.Client{
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if !artworkHosts[strings.ToLower(r.URL.Hostname())] {
				return errUnknownArtworkHost
			}
			return nil
		},
	}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return errPosterUnavailable
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 24<<20))
	if err != nil {
		return err
	}
	return h.store(itemID, kind, body, extensionFor(response.Header.Get("Content-Type")))
}

// store writes the bytes and points the item at them.
func (h ArtworkHandler) store(itemID, kind string, body []byte, extension string) error {
	dir := filepath.Join(h.ImageDir, "chosen")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	path := filepath.Join(dir, itemID+"-"+strings.ToLower(kind)+extension)
	if err := os.WriteFile(path, body, 0o600); err != nil {
		return err
	}
	// A content hash for the tag, so the client's artwork cache — which keys on
	// the tag and never revalidates — shows the new picture immediately rather
	// than the one it already has under the same name.
	return h.Store.SetImage(itemID, kind, path, contentTag(body), len(body))
}

// imageKind accepts the types this server stores, and nothing else: the kind
// becomes part of a filename.
func imageKind(raw string) string {
	switch strings.ToLower(raw) {
	case "primary":
		return "Primary"
	case "backdrop":
		return "Backdrop"
	case "thumb":
		return "Thumb"
	case "logo":
		return "Logo"
	default:
		return ""
	}
}

// contentTag is the cache key a picture is served under.
func contentTag(body []byte) string {
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:16])
}

// sniffExtension names the file by what it actually holds.
func sniffExtension(body []byte, contentType string) string {
	switch {
	case len(body) >= 12 && string(body[:4]) == "RIFF" && string(body[8:12]) == "WEBP":
		return ".webp"
	case len(body) >= 8 && string(body[:8]) == "\x89PNG\r\n\x1a\n":
		return ".png"
	case len(body) >= 3 && body[0] == 0xFF && body[1] == 0xD8 && body[2] == 0xFF:
		return ".jpg"
	case strings.Contains(contentType, "png"):
		return ".png"
	case strings.Contains(contentType, "webp"):
		return ".webp"
	}
	return ".jpg"
}
