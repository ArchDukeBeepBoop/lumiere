package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"path/filepath"
	"strings"
	"time"

	"lumiere-server/internal/anilist"
)

// Key art from AniList: a franchise collection's poster and backdrop, and the
// pictures a matched show is missing.
//
// Monogatari is why: TMDB files it as one show and has no art for most of
// its arcs, so its posters and backdrops were always added by hand. AniList
// has a cover and, for most entries, a wide banner for every one of them.
// Pictures someone chose are never replaced — only ones this server made.

// artTag names a picture by where it came from, so a pass that finds the
// same picture downloads nothing.
func artTag(url string) string {
	sum := sha256.Sum256([]byte(url))
	return "anilist" + hex.EncodeToString(sum[:6])
}

// franchiseName is what a franchise is called in the library most of its
// members are in: by its folders there for a library read by folder names,
// by romaji for one read in romaji, else the usual English-first name. See
// anilist.NameFrom and store.FranchiseNaming.
func (h CollectionSuggestHandler) franchiseName(naming map[string]string, nodes map[int]anilist.Node,
	component []int, members []string, usual string) string {
	count := map[string]int{}
	lead := ""
	for _, m := range members {
		lib := h.Store.ItemLibrary(m)
		if count[lib]++; count[lib] > count[lead] {
			lead = lib
		}
	}
	switch naming[lead] {
	case "folder":
		var folders []string
		for _, m := range members {
			folders = append(folders, h.Store.FolderNameOf(m))
		}
		return anilist.NameFrom(nodes, component, folders)
	case "romaji":
		return anilist.NameFrom(nodes, component, nil)
	}
	return usual
}

// franchiseArtFor is the art a franchise wears: its lead entry's cover, and
// the first banner in the order it came out.
func franchiseArtFor(nodes map[int]anilist.Node, component []int) anilist.Node {
	lead := nodes[anilist.Lead(nodes, component)]
	art := anilist.Node{ID: lead.ID, Cover: lead.Cover}
	if lead.HasBanner() {
		art.Banner = lead.Banner
		return art
	}
	for _, id := range anilist.Chronology(nodes, component) {
		if nodes[id].HasBanner() {
			art.Banner = nodes[id].Banner
			break
		}
	}
	return art
}

// franchiseArt dresses a franchise collection in AniList's art; false when
// it is off or there is none, and the mosaic stands.
func (h CollectionSuggestHandler) franchiseArt(ctx context.Context, id string, art anilist.Node) bool {
	if !h.Store.AniListArtOn() || art.Cover == "" {
		return false
	}
	if ours, _ := h.Store.CollectionPosters(id); !ours {
		return true
	}
	tags := h.Store.ImageTags(id)
	dir := filepath.Join(h.imageDir(), "franchises")
	if tags["Primary"] != artTag(art.Cover) {
		out := filepath.Join(dir, id+"-poster.jpg")
		if downloadCover(ctx, art.Cover, dir, out) != nil {
			return false
		}
		h.Store.SetImage(id, "Primary", out, artTag(art.Cover), 0)
		h.Store.SetItemValue(id, "art:mosaic", "anilist")
	}
	backdrop := tags["Backdrop"]
	if art.Banner != "" && backdrop != artTag(art.Banner) && (backdrop == "" || strings.HasPrefix(backdrop, "anilist")) {
		out := filepath.Join(dir, id+"-backdrop.jpg")
		if downloadCover(ctx, art.Banner, dir, out) == nil {
			h.Store.SetImage(id, "Backdrop", out, artTag(art.Banner), 0)
		}
	}
	return true
}

// showArt gives matched shows and films the poster or backdrop they lack,
// from their own entry; returns how many pictures it added.
func (h CollectionSuggestHandler) showArt(ctx context.Context, nodes map[int]anilist.Node, matched map[int][]string) int {
	if !h.Store.AniListArtOn() {
		return 0
	}
	added := 0
	dir := filepath.Join(h.imageDir(), "anilist")
	for id, items := range matched {
		n, ok := nodes[id]
		if !ok {
			continue
		}
		for _, item := range items {
			if ctx.Err() != nil {
				return added
			}
			tags := h.Store.ImageTags(item)
			for _, pic := range []struct{ kind, url, file string }{
				{"Primary", n.Cover, item + "-poster.jpg"},
				{"Backdrop", n.Banner, item + "-backdrop.jpg"},
			} {
				if tags[pic.kind] != "" || !strings.HasPrefix(pic.url, "https://") {
					continue
				}
				out := filepath.Join(dir, pic.file)
				if downloadCover(ctx, pic.url, dir, out) != nil {
					continue
				}
				h.Store.SetImage(item, pic.kind, out, artTag(pic.url), 0)
				added++
				time.Sleep(200 * time.Millisecond)
			}
		}
	}
	if added > 0 {
		h.Log.Info("anilist: show art", "pictures", added)
	}
	return added
}

// refreshArt re-reads entries cached before banners were asked for, where a
// franchise or a show would use them.
func (h CollectionSuggestHandler) refreshArt(ctx context.Context, c *anilist.Client, nodes map[int]anilist.Node, matched map[int][]string) {
	if !h.Store.AniListArtOn() {
		return
	}
	var stale []int
	for id := range matched {
		if n, ok := nodes[id]; ok && n.Banner == "" {
			stale = append(stale, id)
		}
	}
	for _, component := range anilist.Components(nodes) {
		if lead := anilist.Lead(nodes, component); nodes[lead].Banner == "" && len(matched[lead]) == 0 {
			stale = append(stale, lead)
		}
	}
	for start := 0; start < len(stale) && ctx.Err() == nil; start += 50 {
		fetched, err := c.Fetch(ctx, stale[start:min(start+50, len(stale))])
		if err != nil {
			h.Log.Info("anilist: art refresh stopped", "reason", err)
			return
		}
		for _, n := range fetched {
			h.Store.SaveAniListNode(n)
			nodes[n.ID] = n
		}
	}
}
