package api

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"lumiere-server/internal/metadata"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// IdentifyHandler applies a match the user picked in Lumiere's identify sheet.
//
// This is the endpoint "identify" has always meant, and the one thing about it
// worth knowing is where the work happens. Lumiere searches the provider
// *itself*, with the key the user pasted into its settings, and sends the answer
// here: the ids, the corrected title and year, and a poster URL. Nothing in this
// server needs a TMDB key, because the client already did the part that needs one.
//
// So this does not scrape. It writes down what it was told and fetches the one
// picture named in the request. Overview, cast and backdrops are the scraper's
// job and there is no scraper here — a title corrected from "Movie 2019 1080p"
// to its real name, with the right poster, is most of what anyone opens this
// sheet for.
type IdentifyHandler struct {
	Store    *store.Store
	DataDir  string
	ImageDir string
	Log      *slog.Logger
}

type identifyRequest struct {
	ProviderIds        map[string]string `json:"ProviderIds"`
	Name               string            `json:"Name"`
	ProductionYear     *int              `json:"ProductionYear"`
	ImageURL           string            `json:"ImageUrl"`
	SearchProviderName string            `json:"SearchProviderName"`
}

// artworkHosts is where a poster may be fetched from.
//
// An allowlist because this is the one place the server makes an outbound
// request to a URL that arrived in a request body. The client only ever produces
// these two, and without the list a mistake — or anything that ever reaches this
// endpoint by another route — could ask the server to fetch an address inside
// the network it is running on and report what came back.
var artworkHosts = map[string]bool{
	"image.tmdb.org":       true,
	"artworks.thetvdb.com": true,
}

// Apply is POST /Items/RemoteSearch/Apply/{itemId}.
func (h IdentifyHandler) Apply(w http.ResponseWriter, r *http.Request) {
	itemID := store.NormalizeID(r.PathValue("itemId"))
	if itemID == "" {
		http.NotFound(w, r)
		return
	}

	var req identifyRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}

	if err := h.Store.ApplyIdentification(itemID, store.Identification{
		Name:        strings.TrimSpace(req.Name),
		Year:        req.ProductionYear,
		ProviderIDs: req.ProviderIds,
	}); err != nil {
		if err == store.ErrNoItem {
			http.NotFound(w, r)
			return
		}
		h.Log.Error("identify failed", "error", err, "item", itemID)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not apply"})
		return
	}

	// Artwork last and best-effort: a title corrected without its poster is a
	// success with a gap, and failing the whole call would undo nothing — the
	// name is already written.
	if req.ImageURL != "" {
		if err := h.fetchPoster(itemID, req.ImageURL); err != nil {
			h.Log.Info("identify: poster not fetched", "reason", err, "item", itemID)
		}
	}

	// A season identified by hand: its poster and its episodes' stills come
	// from the show it now names, right away rather than at the next pass.
	// See PendingSeasons for how the season's own match outranks its show's.
	if tmdb := req.ProviderIds["Tmdb"]; tmdb != "" {
		h.enrichSeason(r.Context(), itemID, tmdb, req.ProviderIds["TmdbSeason"])
	}

	h.Log.Info("identified", "item", itemID, "provider", req.SearchProviderName)
	w.WriteHeader(http.StatusNoContent)
}

func (h IdentifyHandler) enrichSeason(ctx context.Context, itemID, tmdbID, number string) {
	var kind string
	var index sql.NullInt64
	if err := h.Store.DB.QueryRow(
		`SELECT type, index_number FROM item WHERE id = ?`, itemID).Scan(&kind, &index); err != nil || kind != "Season" {
		return
	}
	season := PendingSeasonFor(itemID, tmdbID, number, index)
	token := metadata.ReadToken(h.DataDir)
	if token == "" {
		return
	}
	enricher := &metadata.Enricher{
		Store: h.Store, TMDB: metadata.NewTMDB(token), ImageDir: h.ImageDir, Log: h.Log,
	}
	// A fresh identification means the old poster and the old "nothing
	// found" mark are both about a different show.
	h.Store.DB.Exec(`DELETE FROM image WHERE item_id = ? AND kind = 'Primary'`, itemID)
	h.Store.DB.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = 'provider:none'`, itemID)
	h.Store.DB.Exec(`
		DELETE FROM item_value WHERE kind = 'provider:none'
		  AND item_id IN (SELECT id FROM item WHERE parent_id = ? AND type = 'Episode')`, itemID)
	if _, err := enricher.EnrichSeason(ctx, season); err != nil {
		h.Log.Info("identify: season poster not fetched", "item", itemID, "error", err)
	}
	batches, err := enricher.PendingEpisodeArt(50)
	if err != nil {
		return
	}
	for _, batch := range batches {
		if batch.TmdbID == tmdbID && batch.Season == season.Number {
			if _, err := enricher.EnrichEpisodes(ctx, batch); err != nil {
				h.Log.Info("identify: stills not fetched", "item", itemID, "error", err)
			}
		}
	}
}

// PendingSeasonFor builds the season the enricher should ask about: the
// number given with the identification, else the season's own.
func PendingSeasonFor(itemID, tmdbID, number string, index sql.NullInt64) metadata.PendingSeason {
	n := int(index.Int64)
	if parsed, err := strconv.Atoi(number); err == nil && parsed > 0 {
		n = parsed
	}
	if n <= 0 {
		n = 1
	}
	return metadata.PendingSeason{ID: itemID, Number: n, TmdbID: tmdbID}
}

// allowedArtworkURL decides whether a poster URL may be fetched at all.
//
// Separate from the fetch so the decision can be tested without a network: the
// list is the security boundary, and a test that has to reach TMDB to check it
// is one that passes when the machine is offline.
func allowedArtworkURL(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || !artworkHosts[strings.ToLower(u.Hostname())] {
		return nil, errUnknownArtworkHost
	}
	return u, nil
}

func (h IdentifyHandler) fetchPoster(itemID, raw string) error {
	u, err := allowedArtworkURL(raw)
	if err != nil {
		return err
	}

	client := &http.Client{
		Timeout: 20 * time.Second,
		// Redirects are where an allowlist is usually escaped: the first hop is
		// permitted and the second is anywhere at all.
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

	// Capped: an unbounded read from a remote host is a memory budget somebody
	// else controls. A poster is a few hundred KB.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 12<<20))
	if err != nil {
		return err
	}

	sum := sha256.Sum256(body)
	tag := hex.EncodeToString(sum[:16])
	dir := filepath.Join(h.ImageDir, "identified")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	path := filepath.Join(dir, itemID+"-primary"+extensionFor(resp.Header.Get("Content-Type")))
	if err := os.WriteFile(path, body, 0o600); err != nil {
		return err
	}
	// The tag is the content hash, so the client's artwork cache — which keys on
	// the tag and never revalidates — busts exactly when the picture changes.
	return h.Store.SetPrimaryImage(itemID, path, tag, len(body))
}

func extensionFor(contentType string) string {
	switch {
	case strings.Contains(contentType, "png"):
		return ".png"
	case strings.Contains(contentType, "webp"):
		return ".webp"
	default:
		return ".jpg"
	}
}

var (
	errUnknownArtworkHost = &identifyError{"artwork host is not one this server fetches from"}
	errPosterUnavailable  = &identifyError{"the provider did not return the poster"}
)

type identifyError struct{ msg string }

func (e *identifyError) Error() string { return e.msg }
