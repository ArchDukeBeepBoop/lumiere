package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"lumiere-server/internal/anilist"
	"lumiere-server/internal/safefs"
)

// Season posters from AniList, for the seasons TMDB has none for.
//
// Three in four missing season posters were anime: TMDB numbers a long run as
// one season, or not at all, and answered 404 for season 2 of most of them.
// AniList has an entry, with its own cover, for every season — season 2 is
// the sequel of season 1 — so a bare season takes its entry's cover, and a
// Season 0 the franchise's first OVA or special.

// seasonCovers fills bare seasons of matched shows; returns how many.
func (h CollectionSuggestHandler) seasonCovers(ctx context.Context, c *anilist.Client, nodes map[int]anilist.Node, matched map[int][]string) int {
	seriesNode := map[string]int{}
	var series []string
	for id, items := range matched {
		for _, item := range items {
			if _, ok := seriesNode[item]; !ok {
				seriesNode[item] = id
				series = append(series, item)
			}
		}
	}
	bare := h.Store.BareSeasons(series)
	if len(bare) == 0 {
		return 0
	}
	// Which entry each bare season is.
	want := map[string]int{}
	for _, b := range bare {
		chain := anilist.Seasons(nodes, seriesNode[b.SeriesID])
		switch {
		case b.Number == 0:
			if special := anilist.Specials(nodes, chain); special != 0 {
				want[b.ID] = special
			}
		case b.Number >= 1 && b.Number <= len(chain):
			want[b.ID] = chain[b.Number-1]
		}
	}
	// Covers for entries cached before covers were asked for.
	var refetch []int
	for _, id := range want {
		if nodes[id].Cover == "" {
			refetch = append(refetch, id)
		}
	}
	for start := 0; start < len(refetch) && ctx.Err() == nil; start += 50 {
		fetched, err := c.Fetch(ctx, refetch[start:min(start+50, len(refetch))])
		if err != nil {
			break
		}
		for _, n := range fetched {
			h.Store.SaveAniListNode(n)
			nodes[n.ID] = n
		}
	}
	made := 0
	dir := filepath.Join(h.imageDir(), "seasons")
	for _, b := range bare {
		if ctx.Err() != nil {
			break
		}
		cover := nodes[want[b.ID]].Cover
		if want[b.ID] == 0 || cover == "" {
			h.Store.SetItemValue(b.ID, "season:anilist", "none")
			continue
		}
		out := filepath.Join(dir, b.ID+".jpg")
		if err := downloadCover(ctx, cover, dir, out); err != nil {
			h.Log.Info("anilist: season cover not fetched", "season", b.ID, "reason", err)
			continue
		}
		sum := sha256.Sum256([]byte(cover))
		h.Store.SetImage(b.ID, "Primary", out, "anilist"+hex.EncodeToString(sum[:6]), 0)
		h.Store.SetItemValue(b.ID, "season:anilist", strconv.Itoa(want[b.ID]))
		made++
		time.Sleep(200 * time.Millisecond)
	}
	if made > 0 {
		h.Log.Info("anilist: season covers", "count", made)
	}
	return made
}

// downloadCover saves one AniList cover, from AniList's image host only.
func downloadCover(ctx context.Context, url, dir, out string) error {
	if !strings.HasPrefix(url, "https://s4.anilist.co/") {
		return fmt.Errorf("not an AniList image")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(req)
	if err != nil {
		return fmt.Errorf("request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s", resp.Status)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 10<<20))
	if err != nil {
		return err
	}
	os.MkdirAll(dir, 0o755)
	return safefs.WriteFile(dir, out, data, 0o644)
}
