// Package anilist finds anime franchises: every season, film, OVA and
// spin-off of one story, from AniList's relation graph.
//
// TMDB's film series cover Hollywood franchises well and anime barely —
// "Fate" is not a TMDB collection, and a show's later seasons are one series
// there. AniList links each entry to its prequel, sequel, side story and
// spin-off, so a franchise is the connected part of that graph. This file is
// the pure half: matching a local title to an entry, walking the graph, and
// naming what it finds. See client.go for the network half.
package anilist

import (
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// Node is one AniList entry, as much as a franchise needs.
type Node struct {
	ID       int      `json:"id"`
	Romaji   string   `json:"r"`
	English  string   `json:"e,omitempty"`
	Native   string   `json:"n,omitempty"`
	Synonyms []string `json:"s,omitempty"`
	Year     int      `json:"y,omitempty"`
	Format   string   `json:"f,omitempty"` // TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL, MUSIC
	// Cover is the entry's cover image, for season posters. Empty on an
	// entry cached before covers were asked for.
	Cover string `json:"c,omitempty"`
	// Banner is the wide key art, for backdrops: NoBanner when AniList has
	// none, empty on an entry cached before banners were asked for.
	Banner    string `json:"b,omitempty"`
	Relations []Edge `json:"rel,omitempty"`
}

// NoBanner marks an entry asked for its banner that has none.
const NoBanner = "-"

// HasBanner says whether the entry has wide key art.
func (n Node) HasBanner() bool { return n.Banner != "" && n.Banner != NoBanner }

// Edge is one relation from a node.
type Edge struct {
	ID    int    `json:"i"`
	Kind  string `json:"k"` // PREQUEL, SEQUEL, SIDE_STORY, ...
	Anime bool   `json:"a"`
}

// franchiseEdges are the relations that keep two entries in one franchise.
// Adaptation and source point at manga and novels; character and other link
// unrelated stories through a cameo, which would weld Lupin to Detective
// Conan.
var franchiseEdges = map[string]bool{
	"PREQUEL": true, "SEQUEL": true, "PARENT": true, "SIDE_STORY": true,
	"SPIN_OFF": true, "ALTERNATIVE": true, "SUMMARY": true, "COMPILATION": true, "CONTAINS": true,
}

// Follows says whether an edge stays inside the franchise.
func Follows(e Edge) bool { return e.Anime && franchiseEdges[e.Kind] }

// Components groups the given entries into franchises: each is the set of
// known nodes reachable from one another through franchise edges. Edges to
// nodes not in `nodes` are ignored — the caller fetches what it needs first.
func Components(nodes map[int]Node) [][]int {
	parent := map[int]int{}
	var find func(int) int
	find = func(x int) int {
		if parent[x] == 0 || parent[x] == x {
			parent[x] = x
			return x
		}
		parent[x] = find(parent[x])
		return parent[x]
	}
	union := func(a, b int) {
		ra, rb := find(a), find(b)
		if ra != rb {
			if ra < rb {
				parent[rb] = ra
			} else {
				parent[ra] = rb
			}
		}
	}
	for id, n := range nodes {
		find(id)
		for _, e := range n.Relations {
			if _, known := nodes[e.ID]; known && Follows(e) {
				union(id, e.ID)
			}
		}
	}
	groups := map[int][]int{}
	for id := range nodes {
		r := find(id)
		groups[r] = append(groups[r], id)
	}
	var out [][]int
	for _, g := range groups {
		sort.Ints(g)
		out = append(out, g)
	}
	sort.Slice(out, func(i, j int) bool { return out[i][0] < out[j][0] })
	return out
}

// Normalize folds a title for comparison: letters and digits, lower case.
func Normalize(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// Match picks the search result that is this local title: a name that is
// the same once folded, of a compatible kind, and — where both are known —
// within a year. Nothing is better than a near miss: a wrong match files a
// show in someone else's franchise.
//
// A show may also be films on AniList — Kizumonogatari is three films kept
// as one show's folder — but only when no entry of a show's own kind has the
// name.
func Match(name, original string, year int, film bool, results []Node) (Node, bool) {
	name, named := CleanName(name)
	if year == 0 {
		year = named
	}
	want := map[string]bool{Normalize(name): true}
	if original != "" {
		want[Normalize(original)] = true
	}
	delete(want, "")
	for _, relaxed := range []bool{false, true} {
		if relaxed && film {
			break
		}
		for _, n := range results {
			kind := film == (n.Format == "MOVIE") || (film && n.Format == "SPECIAL")
			if relaxed {
				kind = n.Format == "MOVIE"
			}
			if !kind || (year != 0 && n.Year != 0 && (n.Year < year-1 || n.Year > year+1)) {
				continue
			}
			for _, title := range append([]string{n.Romaji, n.English, n.Native}, n.Synonyms...) {
				if title != "" && (want[Normalize(title)] || relaxed && firstPart(title, name)) {
					return n, true
				}
			}
		}
	}
	return Node{}, false
}

// firstPart says whether a film is the first of a series a show folder holds
// under the series' bare name: "Kizumonogatari I: Tekketsu-hen" for a folder
// called Kizumonogatari, which AniList has only as its three parts.
func firstPart(title, name string) bool {
	t, n := strings.ToLower(strings.TrimSpace(title)), strings.ToLower(strings.TrimSpace(name))
	if n == "" || !strings.HasPrefix(t, n) {
		return false
	}
	rest := t[len(n):]
	for _, mark := range []string{" i:", " i ", " part 1", " 1:", " 1 "} {
		if strings.HasPrefix(rest, mark) || rest == strings.TrimRight(mark, ": ") {
			return true
		}
	}
	return false
}

// CleanName drops a year a folder carries in its name — "Kabukimonogatari
// (2013)" is searched as Kabukimonogatari, in 2013 — and returns that year.
func CleanName(name string) (string, int) {
	t := strings.TrimSpace(name)
	if n := len(t); n >= 7 && t[n-1] == ')' && t[n-6] == '(' {
		if y, err := strconv.Atoi(t[n-5 : n-1]); err == nil && y > 1900 && y < 2100 {
			return strings.TrimSpace(t[:n-6]), y
		}
	}
	return t, 0
}

// tvFormats continue a show from season to season.
var tvFormats = map[string]bool{"TV": true, "TV_SHORT": true, "ONA": true}

// Seasons follows a show's sequels from its first entry: the entry for
// season 1, then 2, and so on, as AniList splits a run into one entry per
// season. Films and OVAs in between are stepped over, not counted.
func Seasons(nodes map[int]Node, first int) []int {
	chain := []int{first}
	seen := map[int]bool{first: true}
	current := first
	for len(chain) < 60 {
		next := 0
		queue := []int{current}
		// The next TV entry, through at most a few non-TV sequels.
		for hops := 0; hops < 4 && next == 0 && len(queue) > 0; hops++ {
			var after []int
			for _, id := range queue {
				for _, e := range nodes[id].Relations {
					if e.Kind != "SEQUEL" || seen[e.ID] {
						continue
					}
					seen[e.ID] = true
					if tvFormats[nodes[e.ID].Format] && next == 0 {
						next = e.ID
					} else {
						after = append(after, e.ID)
					}
				}
			}
			queue = after
		}
		if next == 0 {
			return chain
		}
		chain = append(chain, next)
		current = next
	}
	return chain
}

// Specials is the first OVA or special linked to any of these entries — the
// picture for a show's Season 0.
func Specials(nodes map[int]Node, entries []int) int {
	for _, id := range entries {
		for _, e := range nodes[id].Relations {
			if f := nodes[e.ID].Format; (f == "OVA" || f == "SPECIAL") && Follows(e) {
				return e.ID
			}
		}
	}
	return 0
}

// Chronology orders a franchise's entries as they came out — year, then
// AniList's id, which rises as entries are added.
func Chronology(nodes map[int]Node, ids []int) []int {
	out := append([]int(nil), ids...)
	sort.Slice(out, func(i, j int) bool { return earlier(nodes[out[i]], nodes[out[j]]) })
	return out
}
