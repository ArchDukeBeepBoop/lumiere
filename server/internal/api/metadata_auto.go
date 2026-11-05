package api

import (
	"context"
	"errors"
	"fmt"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/metadata"
)

// Artwork without anyone asking.
//
// The naming pass used to run at start, after a scan that found something, and
// when the app's button was pressed — two hundred titles each time. A library
// put back from a cache, or a key entered for the first time, is thousands of
// titles without a poster, and at that rate they waited for weeks of restarts.
// Now the background keeper offers a pass every five minutes, and a pass runs
// when there is something to look up. It works through the backlog a pass at
// a time, then idles at the cost of four small queries.
//
// Never while something plays — the keeper does not tick then, and a pass
// already running stops at its next lookup — and never with a key TMDB has
// refused: one refusal ends the pass and is remembered until the key changes.

// StartIfPending is the keeper's hook: a pass, if there is a key TMDB has not
// refused and anything a pass would do.
func (h *MetadataHandler) StartIfPending() bool {
	token := metadata.ReadToken(h.DataDir)
	h.mu.Lock()
	refused := token != "" && token == h.rejected
	h.mu.Unlock()
	if token == "" || refused || (!h.identifyAllRequested() && !h.anythingPending(token)) {
		return false
	}
	return h.Start()
}

func (h *MetadataHandler) anythingPending(token string) bool {
	e := &metadata.Enricher{Store: h.Store, TMDB: metadata.NewTMDB(token), ImageDir: h.ImageDir, Log: h.Log}
	if items, _ := e.PendingItems(1); len(items) > 0 {
		return true
	}
	if media.PendingMusicCovers(h.Store.DB) {
		return true
	}
	if located, _ := e.PendingCountries(1); len(located) > 0 {
		return true
	}
	if seasons, _ := e.PendingSeasons(1); len(seasons) > 0 {
		return true
	}
	batches, _ := e.PendingEpisodeArt(1)
	return len(batches) > 0
}

// shouldStop ends a pass on a refused key or on playback starting.
func (h *MetadataHandler) shouldStop(token string, err error) bool {
	if errors.Is(err, metadata.ErrKeyRejected) {
		h.mu.Lock()
		h.rejected = token
		h.progress.Error = "TMDB refused the key. Check it in Settings."
		h.mu.Unlock()
		h.Log.Warn("metadata: TMDB refused the key; automatic lookups wait for a new one")
		return true
	}
	if h.Store.RecentlyPlaying(3 * time.Minute) {
		h.Log.Info("metadata: pass paused for playback")
		return true
	}
	return false
}

// artwork is the season and episode stages of a pass. True means stop.
func (h *MetadataHandler) artwork(ctx context.Context, enricher *metadata.Enricher, token string) bool {
	// Then the seasons, which borrow the show's poster until they have one of
	// their own — the reason every season of a new show looks identical.
	seasons, err := enricher.PendingSeasons(perPass)
	if err != nil {
		h.Log.Error("metadata: could not list seasons", "error", err)
	}
	for _, season := range seasons {
		h.mu.Lock()
		h.progress.Current = season.Series + " — season " + fmt.Sprint(season.Number)
		h.mu.Unlock()

		got, err := enricher.EnrichSeason(ctx, season)
		if h.shouldStop(token, err) {
			return true
		}
		if err != nil {
			h.Log.Info("metadata: no season art", "series", season.Series, "reason", err)
		}
		if got {
			h.mu.Lock()
			h.progress.Named++
			h.mu.Unlock()
		}
		time.Sleep(betweenRequests)
	}

	// Then the episode stills, batched by season: TMDB returns a whole season
	// in one response, so a season of twenty-four episodes costs one request.
	batches, err := enricher.PendingEpisodeArt(episodesPerPass)
	if err != nil {
		h.Log.Error("metadata: could not list episode art", "error", err)
	}
	for _, batch := range batches {
		h.mu.Lock()
		h.progress.Current = fmt.Sprintf("%s — season %d artwork",
			batch.SeriesName, batch.Season)
		h.mu.Unlock()

		stored, err := enricher.EnrichEpisodes(ctx, batch)
		if h.shouldStop(token, err) {
			return true
		}
		if err != nil {
			h.Log.Info("metadata: no episode art",
				"series", batch.SeriesName, "reason", err)
		}
		h.mu.Lock()
		h.progress.Named += stored
		h.mu.Unlock()
		time.Sleep(betweenRequests)
	}

	return false
}
