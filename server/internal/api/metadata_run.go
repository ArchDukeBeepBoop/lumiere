package api

import (
	"context"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/metadata"
)

// The naming pass itself. Split from metadata.go for the 300-line rule.

func (h *MetadataHandler) run(token string) {
	defer func() {
		h.mu.Lock()
		h.running = false
		h.progress.Running = false
		h.progress.Current = ""
		h.mu.Unlock()
	}()

	enricher := &metadata.Enricher{
		Store: h.Store, TMDB: metadata.NewTMDB(token),
		ImageDir: h.ImageDir, Log: h.Log,
	}
	everything := h.identifyAllRequested()
	ctx := context.Background()
	seen := map[string]bool{}
	// One batch normally; batch after batch for "identify everything", until
	// nothing unmatched is left. Every item leaves the set — named, or marked
	// asked-and-missed — so the loop ends.
	for batch := 0; ; batch++ {
		var pending []metadata.Pending
		var err error
		if everything {
			pending, err = enricher.UnmatchedItems(perPass)
		} else if batch == 0 {
			pending, err = enricher.PendingItems(perPass)
		}
		if err != nil {
			h.Log.Error("metadata: could not list pending", "error", err)
			h.mu.Lock()
			h.progress.Error = err.Error()
			h.mu.Unlock()
			return
		}
		// A title whose lookup failed (not missed — failed, a network error)
		// is still unmatched and would come back in the next batch for ever.
		// Each is asked once per pass.
		fresh := pending[:0]
		for _, item := range pending {
			if !seen[item.ID] {
				seen[item.ID] = true
				fresh = append(fresh, item)
			}
		}
		pending = fresh
		if len(pending) == 0 {
			if everything {
				// Done: every unmatched title has been asked once.
				h.Store.SetMeta(IdentifyAllKey, "")
				h.Log.Info("metadata: identify-all complete")
			}
			break
		}
		if h.nameAll(ctx, enricher, token, pending) {
			return
		}
		if !everything {
			break
		}
	}
	h.creditsAndRest(ctx, enricher, token)
}

// nameAll names one batch; true when the pass must stop.
func (h *MetadataHandler) nameAll(ctx context.Context, enricher *metadata.Enricher, token string, pending []metadata.Pending) bool {
	for _, item := range pending {
		h.mu.Lock()
		h.progress.Current = item.Name
		h.mu.Unlock()

		named, err := enricher.Enrich(ctx, item)
		if h.shouldStop(token, err) {
			return true
		}
		if err != nil {
			// One title that will not resolve is not a pass that should stop:
			// the rest of the library is still worth naming.
			h.Log.Info("metadata: not named", "item", item.Name, "reason", err)
		}

		h.mu.Lock()
		if named {
			h.progress.Named++
		} else {
			h.progress.Missed++
		}
		h.mu.Unlock()

		time.Sleep(betweenRequests)
	}
	return false
}

// creditsAndRest is the rest of a pass: credits, artwork, orders, frames.
func (h *MetadataHandler) creditsAndRest(ctx context.Context, enricher *metadata.Enricher, token string) {
	// Then the credits of anything matched before the pass learned to ask
	// for them — a film named by an earlier version, a show the import
	// brought without its cast.
	uncredited, err := enricher.PendingCredits(perPass)
	if err != nil {
		h.Log.Error("metadata: could not list uncredited", "error", err)
	}
	for _, item := range uncredited {
		h.mu.Lock()
		h.progress.Current = item.Name + " — cast"
		h.mu.Unlock()
		_, err := enricher.Credit(ctx, item, item.Type == "Series")
		if h.shouldStop(token, err) {
			return
		}
		if err != nil {
			h.Log.Info("metadata: credits not fetched", "item", item.Name, "reason", err)
		}
		time.Sleep(betweenRequests)
	}

	// Where each matched title comes from, for the country filter — titles
	// matched before the pass asked. One request each, a batch per pass.
	located, err := enricher.PendingCountries(perPass)
	if err != nil {
		h.Log.Error("metadata: could not list titles without a country", "error", err)
	}
	for _, item := range located {
		h.mu.Lock()
		h.progress.Current = item.Name + " — country"
		h.mu.Unlock()
		err := enricher.Country(ctx, item)
		if h.shouldStop(token, err) {
			return
		}
		if err != nil {
			h.Log.Info("metadata: country not fetched", "item", item.Name, "reason", err)
		}
		time.Sleep(betweenRequests)
	}

	if h.artwork(ctx, enricher, token) {
		return
	}

	// Then a few shows whose folders follow one of TMDB's other orders. See
	// metadata.SuggestOrders.
	if n := enricher.SuggestOrders(ctx, 10); n > 0 {
		h.Log.Info("metadata: episode orders suggested", "shows", n)
	}

	// What TMDB could not name keeps the title its file carries. See
	// store.TitleUnmatchedEpisodes.
	if titled, err := h.Store.TitleUnmatchedEpisodes(); err != nil {
		h.Log.Error("metadata: file titles failed", "error", err)
	} else if titled > 0 {
		h.Log.Info("metadata: episodes titled from their files", "count", titled)
	}

	// A season or specials in a folder of their own, now matched to the show
	// already here, folded into it. See store.MergeSplitShows.
	h.Store.MergeSplitShows(h.Log)

	h.Log.Info("metadata pass complete",
		"named", h.progress.Named, "missed", h.progress.Missed)

	// Whatever is still bare gets a frame. After naming, never before: a
	// poster is the better picture, and this must only fill what the
	// providers could not. See media.Frames.
	h.mu.Lock()
	h.progress.Current = "Taking frames for files with no picture"
	h.mu.Unlock()
	if _, err := media.Frames(h.Store.DB, media.FindFFmpeg(), h.ImageDir, 500, h.Log); err != nil {
		h.Log.Error("frames: pass failed", "error", err)
	}
	// And albums: the picture in the folder or inside the first track. See
	// media.MusicCovers.
	h.mu.Lock()
	h.progress.Current = "Finding album covers"
	h.mu.Unlock()
	if _, err := media.MusicCovers(h.Store.DB, media.FindFFmpeg(), h.ImageDir, 300, h.Log); err != nil {
		h.Log.Error("covers: pass failed", "error", err)
	}
}

// IdentifyAllKey holds a pending "identify everything" request — POST
// /Metadata/Run?scope=all — until a pass has asked about every unmatched film
// and show. It survives a pass paused for playback and a restart; the keeper
// starts a pass while it is set.
const IdentifyAllKey = "metadata_identify_all"

func (h *MetadataHandler) identifyAllRequested() bool {
	value, _ := h.Store.Meta(IdentifyAllKey)
	return value != ""
}
