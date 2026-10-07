package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// EpisodeImagesHandler fills in stills for episodes that have none.
//
// The same division of labour as identify, for the same reason: Lumiere holds
// the TMDB key and does the looking-up, and this server writes down what it is
// told and fetches the pictures named. No third-party credential lives here.
//
// What it will not do is replace a picture. Only episodes with no Primary image
// are offered, and the client is told which ones — so a still Jellyfin scraped,
// or a frame someone grabbed from the file, survives a fetch untouched.
type EpisodeImagesHandler struct {
	Store    *store.Store
	ImageDir string
	Log      *slog.Logger
}

// Pending is GET /Shows/{seriesId}/EpisodeImages/Pending.
//
// The client asks what is missing rather than guessing: it has no idea which
// episodes already carry artwork, and fetching a whole season from TMDB to
// discard most of it is a request per episode nobody needed.
func (h EpisodeImagesHandler) Pending(w http.ResponseWriter, r *http.Request) {
	seriesID := store.NormalizeID(r.PathValue("seriesId"))
	if seriesID == "" {
		http.NotFound(w, r)
		return
	}

	targets, err := h.Store.EpisodesWithoutImages(seriesID)
	if err != nil {
		h.Log.Error("pending episode images failed", "error", err, "series", seriesID)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	tmdb, err := h.Store.ProviderID(seriesID, "Tmdb")
	if err != nil {
		h.Log.Error("provider lookup failed", "error", err, "series", seriesID)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}

	type episode struct {
		Id            string `json:"Id"`
		SeasonNumber  int    `json:"SeasonNumber"`
		EpisodeNumber int    `json:"EpisodeNumber"`
	}
	out := make([]episode, 0, len(targets))
	for _, t := range targets {
		out = append(out, episode{t.ID, t.Season, t.Episode})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"TmdbId":   tmdb,
		"Episodes": out,
	})
}

type episodeImageRequest struct {
	Images []struct {
		ItemId   string `json:"ItemId"`
		ImageUrl string `json:"ImageUrl"`
	} `json:"Images"`
}

// maxEpisodeImages caps one request, and with it the outbound work a single call
// can ask for: 500 stills is a long series in one pass and still bounded.
const maxEpisodeImages = 500

// Apply is POST /Shows/{seriesId}/EpisodeImages.
func (h EpisodeImagesHandler) Apply(w http.ResponseWriter, r *http.Request) {
	seriesID := store.NormalizeID(r.PathValue("seriesId"))
	if seriesID == "" {
		http.NotFound(w, r)
		return
	}

	var req episodeImageRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 4<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	if len(req.Images) > maxEpisodeImages {
		writeJSON(w, http.StatusBadRequest, errorBody{"too many images in one request"})
		return
	}

	// Re-read what is actually missing rather than trusting the body. The client
	// asked a moment ago; between then and now a sync may have filled some in,
	// and this is also what stops a request naming an episode of another series.
	allowed := map[string]bool{}
	targets, err := h.Store.EpisodesWithoutImages(seriesID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	for _, t := range targets {
		allowed[t.ID] = true
	}

	fetched, skipped := 0, 0
	for _, image := range req.Images {
		id := store.NormalizeID(image.ItemId)
		if id == "" || !allowed[id] {
			skipped++
			continue
		}
		if err := h.fetchStill(id, image.ImageUrl); err != nil {
			// One still that will not download is not a failed run: a series is
			// dozens of them and the rest are worth having.
			h.Log.Info("episode still not fetched", "reason", err, "item", id)
			skipped++
			continue
		}
		fetched++
	}

	h.Log.Info("episode images", "series", seriesID, "fetched", fetched, "skipped", skipped)
	writeJSON(w, http.StatusOK, map[string]int{"Fetched": fetched, "Skipped": skipped})
}

// fetchStill downloads one episode still and files it as that episode's Primary
// image.
//
// Shares identify's allowlist and redirect policy — `allowedArtworkURL` and the
// check on every hop — because this is the same risk in the same shape: an
// outbound request to a URL that arrived in a request body.
func (h EpisodeImagesHandler) fetchStill(itemID, raw string) error {
	u, err := allowedArtworkURL(raw)
	if err != nil {
		return err
	}

	client := &http.Client{
		Timeout: 20 * time.Second,
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if !artworkHosts[strings.ToLower(r.URL.Hostname())] {
				return errUnknownArtworkHost
			}
			return nil
		},
	}
	resp, err := client.Get(u.String())
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return errPosterUnavailable
	}

	// A still is smaller than a poster; the cap is the same because the point of
	// it is that the size is somebody else's to choose.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 12<<20))
	if err != nil {
		return err
	}

	sum := sha256.Sum256(body)
	tag := hex.EncodeToString(sum[:16])
	dir := filepath.Join(h.ImageDir, "episodes")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	path := filepath.Join(dir, itemID+"-primary"+extensionFor(resp.Header.Get("Content-Type")))
	if err := os.WriteFile(path, body, 0o600); err != nil {
		return err
	}
	return h.Store.SetPrimaryImage(itemID, path, tag, len(body))
}
