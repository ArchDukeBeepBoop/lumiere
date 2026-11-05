package anilist

import "strings"

// Naming a franchise. Split from franchise.go for the 300-line rule.

// Name is what a franchise is called: the earliest TV series or film in it,
// in English where AniList has it, without its season or part.
func Name(nodes map[int]Node, ids []int) string {
	best := Lead(nodes, ids)
	// The words most of its entries share — "Lupin III", "Initial D",
	// "Fate" — before the earliest entry's own title, which is as often a
	// pilot or a side story as the show itself.
	n := nodes[best]
	title := n.English
	if title == "" {
		title = n.Romaji
	}
	first := BaseTitle(title)
	for _, pick := range []func(Node) string{
		func(n Node) string { return n.English }, func(n Node) string { return n.Romaji },
	} {
		shared := sharedPrefix(nodes, ids, pick)
		if shared == "" {
			continue
		}
		// One word of a two-word title is half a name: "Chainsaw" is
		// Chainsaw Man, "Eureka" Eureka Seven.
		if !strings.ContainsAny(shared, " /") && len(strings.Fields(first)) == 2 &&
			strings.HasPrefix(strings.ToLower(first), strings.ToLower(shared)+" ") {
			return first
		}
		return shared
	}
	// Or the ending they share: Bakemonogatari, Nisemonogatari and
	// Kizumonogatari are all Monogatari.
	if ending := sharedEnding(nodes, ids); ending != "" {
		return ending
	}
	return first
}

// NameFrom names a franchise in a library that goes by folder names or by
// romaji (the app's per-library Title Order): the folder name its folders
// share — "Hoshi" for Hoshi and Hoshi Twins — when folders count; then
// the name most of its entries share in romaji, the one it is known by; then
// its first entry's romaji; and the English name only last. folders is nil
// for a romaji library.
func NameFrom(nodes map[int]Node, ids []int, folders []string) string {
	if name := FolderName(folders); name != "" {
		return name
	}
	if shared := sharedPrefix(nodes, ids, func(n Node) string { return n.Romaji }); shared != "" {
		return shared
	}
	if ending := sharedEnding(nodes, ids); ending != "" {
		return ending
	}
	if romaji := BaseTitle(nodes[Lead(nodes, ids)].Romaji); romaji != "" {
		return romaji
	}
	return Name(nodes, ids)
}

// FolderName is the name a franchise's folders share, without a year or a
// season: the words most of them begin with, or the one folder when there is
// only one. "" when they share nothing.
func FolderName(folders []string) string {
	seen := map[string]bool{}
	var names []string
	for _, f := range folders {
		name, _ := CleanName(f)
		if name = BaseTitle(name); name != "" && !seen[strings.ToLower(name)] {
			seen[strings.ToLower(name)] = true
			names = append(names, name)
		}
	}
	if len(names) == 1 {
		return names[0]
	}
	return sharedPrefixOf(names)
}

// Lead is the entry a franchise is named and pictured by: its earliest TV
// series or film, or its earliest entry of any kind.
func Lead(nodes map[int]Node, ids []int) int {
	best := 0
	for _, id := range ids {
		n := nodes[id]
		if n.Format != "TV" && n.Format != "MOVIE" && n.Format != "ONA" {
			continue
		}
		if best == 0 || earlier(n, nodes[best]) {
			best = id
		}
	}
	if best == 0 && len(ids) > 0 {
		best = ids[0]
		for _, id := range ids {
			if earlier(nodes[id], nodes[best]) {
				best = id
			}
		}
	}
	return best
}

// sharedEnding is the longest ending, of six letters or more, that the first
// words of three in four romaji titles share, when they are not all one word:
// "monogatari" across Bakemonogatari, Nisemonogatari, Monogatari Series.
func sharedEnding(nodes map[int]Node, ids []int) string {
	var firsts []string
	distinct := map[string]bool{}
	for _, id := range ids {
		if words := strings.Fields(strings.ToLower(nodes[id].Romaji)); len(words) > 0 {
			w := Normalize(words[0])
			firsts = append(firsts, w)
			distinct[w] = true
		}
	}
	if len(firsts) < 3 || len(distinct) < 2 {
		return ""
	}
	best := ""
	for w := range distinct {
		for cut := 0; len(w)-cut >= 6; cut++ {
			ending := w[cut:]
			if len(ending) <= len(best) {
				break
			}
			shared := 0
			for _, f := range firsts {
				if strings.HasSuffix(f, ending) {
					shared++
				}
			}
			if shared*4 >= len(firsts)*3 {
				best = ending
				break
			}
		}
	}
	if best == "" {
		return ""
	}
	return strings.ToUpper(best[:1]) + best[1:]
}

// sharedPrefix is the longest run of leading words that three in four of the
// entries' titles begin with, or "" when there is none of two characters.
func sharedPrefix(nodes map[int]Node, ids []int, title func(Node) string) string {
	var texts []string
	for _, id := range ids {
		texts = append(texts, title(nodes[id]))
	}
	return sharedPrefixOf(texts)
}

// sharedPrefixOf is sharedPrefix over plain names.
func sharedPrefixOf(texts []string) string {
	var titles [][]string
	for _, t := range texts {
		if t = strings.TrimSpace(t); t != "" {
			titles = append(titles, splitWords(t))
		}
	}
	if len(titles) < 2 {
		return ""
	}
	best := ""
	for _, words := range titles {
		for n := 1; n <= len(words); n++ {
			candidate := words[:n]
			shared := 0
			for _, other := range titles {
				if hasPrefixWords(other, candidate) {
					shared++
				}
			}
			if shared*4 < len(titles)*3 {
				break
			}
			if joined := cleanPrefix(strings.Join(candidate, "")); len(joined) > len(best) {
				best = joined
			}
		}
	}
	if len([]rune(best)) < 2 {
		return ""
	}
	// Stopped part-way through a subtitle no entry is called by: "Code
	// Geass: Lelouch" is "Code Geass".
	if colon := strings.Index(best, ":"); colon > 0 {
		whole := false
		for _, words := range titles {
			if strings.EqualFold(cleanPrefix(strings.Join(words, "")), best) {
				whole = true
			}
		}
		if !whole {
			best = strings.TrimSpace(best[:colon])
		}
	}
	return best
}

// splitWords keeps each word with what follows it, so joining gives the text
// back exactly: "Fate/stay night" → "Fate/", "stay ", "night".
func splitWords(s string) []string {
	var out []string
	start := 0
	for i, r := range s {
		if r == ' ' || r == '/' || r == ':' {
			out = append(out, s[start:i+1])
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}

func hasPrefixWords(words, prefix []string) bool {
	if len(words) < len(prefix) {
		return false
	}
	for i, w := range prefix {
		last := i == len(prefix)-1
		a, b := strings.ToLower(strings.TrimSpace(words[i])), strings.ToLower(strings.TrimSpace(w))
		if last {
			a, b = strings.TrimRight(a, ":/"), strings.TrimRight(b, ":/")
		}
		if a != b {
			return false
		}
	}
	return true
}

// trailingWords are not where a name ends: "El Hazard: The", "Lelouch of the".
var trailingWords = map[string]bool{"the": true, "of": true, "a": true, "an": true, "and": true, "no": true, "to": true, "in": true, "chapter": true, "part": true}

// genericWords alone are not a franchise: "Mobile" is half of Mobile Suit
// Gundam and Mobile Fighter G Gundam, and names neither.
var genericWords = map[string]bool{"mobile": true, "new": true, "super": true, "great": true, "the": true,
	"my": true, "little": true, "shin": true, "kidou": true, "space": true, "magical": true, "black": true}

func cleanPrefix(s string) string {
	trim := func(t string) string { return strings.TrimRight(strings.TrimSpace(t), ":/-–— ") }
	s = trim(s)
	for {
		i := strings.LastIndex(s, " ")
		if i < 0 || !trailingWords[strings.ToLower(s[i+1:])] {
			break
		}
		s = trim(s[:i])
	}
	if !strings.Contains(s, " ") && (genericWords[strings.ToLower(s)] || trailingWords[strings.ToLower(s)]) {
		return ""
	}
	return BaseTitle(s)
}

func earlier(a, b Node) bool {
	if a.Year != b.Year && a.Year != 0 && b.Year != 0 {
		return a.Year < b.Year
	}
	return a.ID < b.ID
}

// seasonMarks are suffixes a franchise's name should not carry.
var seasonMarks = []string{" season ", " 2nd season", " 3rd season", " part ", " cour ", " the movie", " movie", " (movie)", ": pilot film", " pilot film", " 1st stage"}

// BaseTitle drops a season, part or "the movie" from a title's end:
// "Attack on Titan Season 2" → "Attack on Titan".
func BaseTitle(title string) string {
	t := strings.TrimSpace(title)
	lower := strings.ToLower(t)
	for _, mark := range seasonMarks {
		if i := strings.LastIndex(lower, mark); i > 0 {
			t, lower = strings.TrimSpace(t[:i]), lower[:i]
		}
	}
	return strings.TrimRight(strings.TrimSpace(t), ":-–—")
}
