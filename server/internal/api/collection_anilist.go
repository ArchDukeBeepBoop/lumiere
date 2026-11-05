package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"

	"lumiere-server/internal/anilist"
	"lumiere-server/internal/mosaic"
	"lumiere-server/internal/store"
)

// Anime franchises, from AniList.
//
// Each title in the chosen libraries (see store.AniListLibraries) is found on
// AniList once; the walk then reads every entry linked to it as a prequel,
// sequel, side story or spin-off, and each connected group with at least two
// titles in the library becomes a collection — Fate, Monogatari, Gundam —
// kept in step as titles come and go. A group already covered by another
// collection (a TMDB film series, one made by hand) is left alone.

// minFranchise: one title is a show, not a franchise.
const minFranchise = 2

// maxWalk bounds the entries one pass reads; Gundam alone is hundreds.
const maxWalk = 6000

var anilistRunning sync.Mutex

// AniListFranchises runs one pass; returns collections made and changed.
func (h CollectionSuggestHandler) AniListFranchises(ctx context.Context, lookups int) (made, changed int) {
	if !anilistRunning.TryLock() {
		return 0, 0
	}
	defer anilistRunning.Unlock()
	client := anilist.NewClient()
	folders, _ := h.Store.AniListLibraries(h.privateViews())
	if n := h.Store.AniListRecheck(folders); n > 0 {
		h.Log.Info("anilist: titles not found put back to look up again", "count", n)
	}
	h.matchAniList(ctx, client, folders, lookups)

	matched := h.Store.AniListMatched()
	nodes := h.walkAniList(ctx, client, matched)
	h.refreshArt(ctx, client, nodes, matched)
	rooms := h.Store.LibraryRooms(h.privateViews())
	naming := h.Store.FranchiseNaming()
	for _, component := range anilist.Components(nodes) {
		members := map[string]bool{}
		for _, id := range component {
			for _, item := range matched[id] {
				members[item] = true
			}
		}
		if len(members) < minFranchise {
			continue
		}
		name := anilist.Name(nodes, component)
		key := strconv.Itoa(component[0])
		art := franchiseArtFor(nodes, component)
		// As it came out: each title placed by its earliest entry.
		rank := map[string]int{}
		for i, id := range anilist.Chronology(nodes, component) {
			for _, item := range matched[id] {
				if r, seen := rank[item]; !seen || i < r {
					rank[item] = i
				}
			}
		}
		byRoom := map[bool][]string{}
		for m := range members {
			lib := h.Store.ItemLibrary(m)
			if rooms.Excluded[lib] {
				continue
			}
			byRoom[rooms.Private[lib]] = append(byRoom[rooms.Private[lib]], m)
		}
		for private, list := range byRoom {
			sort.SliceStable(list, func(i, j int) bool { return rank[list[i]] < rank[list[j]] })
			m, c := h.keepFranchise(ctx, h.franchiseName(naming, nodes, component, list, name), key, private, list, art)
			made += m
			changed += c
		}
	}
	if made+changed > 0 {
		h.Log.Info("collections: anime franchises", "made", made, "changed", changed)
	}
	h.seasonCovers(ctx, client, nodes, matched)
	h.showArt(ctx, nodes, matched)
	return made, changed
}

// matchAniList finds unchecked titles on AniList, eight to a request: by
// name, without a year the folder carries, and then — for what that missed —
// by original title. A folder called 化物語 is found by its Japanese name; one
// called "Monogatari" only that way, since the search for the bare word
// answers with every other story.
func (h CollectionSuggestHandler) matchAniList(ctx context.Context, c *anilist.Client, folders []string, lookups int) {
	todo := h.Store.AniListUnchecked(folders, lookups)
	byName := func(t store.AniListCandidate) string { name, _ := anilist.CleanName(t.Name); return name }
	missed, ok := h.searchAniList(ctx, c, todo, byName)
	if !ok {
		return
	}
	var again, none []store.AniListCandidate
	for _, t := range missed {
		if t.Original != "" && anilist.Normalize(t.Original) != anilist.Normalize(byName(t)) {
			again = append(again, t)
		} else {
			none = append(none, t)
		}
	}
	if missed, ok = h.searchAniList(ctx, c, again, func(t store.AniListCandidate) string { return t.Original }); !ok {
		return
	}
	for _, t := range append(none, missed...) {
		h.Store.SetAniListMatch(t.ID, 0, "")
	}
}

// searchAniList looks titles up by one of their names and records what
// matches; returns the rest, or false when AniList stopped answering.
func (h CollectionSuggestHandler) searchAniList(ctx context.Context, c *anilist.Client, todo []store.AniListCandidate,
	title func(store.AniListCandidate) string) ([]store.AniListCandidate, bool) {
	var missed []store.AniListCandidate
	for start := 0; start < len(todo); start += 8 {
		if ctx.Err() != nil {
			return nil, false
		}
		batch := todo[start:min(start+8, len(todo))]
		titles := make([]string, len(batch))
		for i, t := range batch {
			titles[i] = title(t)
		}
		results, err := c.Search(ctx, titles)
		if err != nil {
			h.Log.Info("anilist: search stopped", "reason", err)
			return nil, false
		}
		for i, t := range batch {
			if n, ok := anilist.Match(t.Name, t.Original, t.Year, t.Film, results[i]); ok {
				h.Store.SaveAniListNode(n)
				h.Store.SetAniListMatch(t.ID, n.ID, n.Romaji)
			} else {
				missed = append(missed, t)
			}
		}
	}
	return missed, true
}

// walkAniList reads every entry linked to a matched one, from the cache
// where it can and fifty at a time where it cannot.
func (h CollectionSuggestHandler) walkAniList(ctx context.Context, c *anilist.Client, matched map[int][]string) map[int]anilist.Node {
	nodes := map[int]anilist.Node{}
	var queue []int
	for id := range matched {
		queue = append(queue, id)
	}
	sort.Ints(queue)
	queued := map[int]bool{}
	for _, id := range queue {
		queued[id] = true
	}
	for len(queue) > 0 && len(nodes) < maxWalk && ctx.Err() == nil {
		var missing []int
		for _, id := range queue {
			if n, ok := h.Store.AniListNode(id); ok {
				nodes[id] = n
			} else {
				missing = append(missing, id)
			}
		}
		for start := 0; start < len(missing) && ctx.Err() == nil; start += 50 {
			fetched, err := c.Fetch(ctx, missing[start:min(start+50, len(missing))])
			if err != nil {
				h.Log.Info("anilist: walk stopped", "reason", err)
				return nodes
			}
			for _, n := range fetched {
				h.Store.SaveAniListNode(n)
				nodes[n.ID] = n
			}
		}
		var next []int
		for _, id := range queue {
			for _, e := range nodes[id].Relations {
				if anilist.Follows(e) && !queued[e.ID] {
					queued[e.ID] = true
					next = append(next, e.ID)
				}
			}
		}
		queue = next
	}
	return nodes
}

// keepFranchise makes or updates one franchise collection.
func (h CollectionSuggestHandler) keepFranchise(ctx context.Context, name, key string, private bool, members []string, art anilist.Node) (made, changed int) {
	room := "library"
	if private {
		room = "room"
	}
	marker := key + ":" + room
	existing := h.Store.CollectionWithValue("anilist:franchise", marker)
	if existing == "" && h.Store.CoveredByCollection(name, members) {
		return 0, 0
	}
	if existing != "" {
		// Renamed as the naming improves, unless someone named it by hand.
		if h.Store.ItemValue(existing, "lock:name") == "" {
			h.Store.DB.Exec(`UPDATE item SET name = ?, sort_name = ? WHERE id = ? AND name <> ?`, name, name, existing, name)
		}
		a, r := h.Store.SyncLinks(existing, members)
		h.Store.SetLinkOrder(existing, members)
		dressed := h.franchiseArt(ctx, existing, art)
		// Back to the mosaic when AniList's art was turned off.
		undressed := !dressed && strings.HasPrefix(h.Store.ImageTags(existing)["Primary"], "anilist")
		if (a+r > 0 && !dressed) || undressed {
			h.franchisePoster(existing)
		}
		if a+r > 0 {
			return 0, 1
		}
		return 0, 0
	}
	library := ""
	if private {
		library = h.Store.ItemLibrary(members[0])
	}
	id, err := h.Store.CreateCollectionIn(name, library, members)
	if err != nil {
		return 0, 0
	}
	h.Store.SetItemValue(id, "anilist:franchise", marker)
	h.Store.SetLinkOrder(id, members)
	if !h.franchiseArt(ctx, id, art) {
		h.franchisePoster(id)
	}
	return 1, 0
}

// franchisePoster is the four-poster mosaic every made collection gets.
func (h CollectionSuggestHandler) franchisePoster(id string) {
	ours, posters := h.Store.CollectionPosters(id)
	if !ours || len(posters) == 0 {
		return
	}
	sum := sha256.Sum256([]byte(strings.Join(posters, "\n")))
	dir := h.imageDir()
	os.MkdirAll(dir, 0o755)
	out := filepath.Join(dir, id+"-mosaic.jpg")
	if mosaic.Compose(posters, out) == nil {
		h.Store.SetImage(id, "Primary", out, "mosaic"+hex.EncodeToString(sum[:6]), 0)
		h.Store.SetItemValue(id, "art:mosaic", "1")
	}
}
