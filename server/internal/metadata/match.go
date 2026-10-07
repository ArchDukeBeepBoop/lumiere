// Package metadata gives the library its own metadata, without Jellyfin.
//
// The scanner answers what exists; this answers what it is. Between them the
// server stops needing Jellyfin for anything but the history already imported.
//
// The credential lives here rather than in the client, and that is the change of
// principle: identify and the episode-image fetcher deliberately kept the key in
// Lumiere and had the server write down what it was told, because the server was
// a mirror and had no business scraping. A server that catalogues its own disk
// has to be able to name what it found without an app being open.
package metadata

import (
	"strings"
	"unicode"
)

// Candidate is one result a provider offered.
type Candidate struct {
	ID    string
	Title string
	Year  int
	// Popularity is the provider's own ranking. Used only to break ties — it
	// says which title is talked about most, not which one this folder is.
	Popularity float64
	// Overview and Poster are carried for the Identify sheet, which shows a
	// person the candidates rather than picking one. The matcher ignores
	// them.
	Overview string
	Poster   string
}

// Best picks the result a folder most likely means.
//
// Pure, and it carries the whole risk of the feature: a wrong match does not
// fail, it silently renames somebody's show and hangs the wrong artwork on it.
// So the rules are ordered by how much they actually prove, and a weak match is
// no match at all.
//
//   - An exact title match in the right year is the answer.
//   - An exact title match with no year to check is next: the folder said a
//     name and the provider has that name.
//   - A normalised match — case, punctuation and articles removed — is next,
//     because "Dr. STONE" and "Dr Stone" are the same show and every library
//     has a hundred of those.
//   - Nothing else. A fuzzy or first-result match is how a library ends up
//     with Blade Runner's poster on Blade.
func Best(query string, year int, candidates []Candidate) (Candidate, bool) {
	normalisedQuery := Normalise(query)

	var exactSameYear, exactAnyYear, normalised []Candidate
	for _, candidate := range candidates {
		switch {
		case strings.EqualFold(candidate.Title, query) && year > 0 && candidate.Year == year:
			exactSameYear = append(exactSameYear, candidate)
		case strings.EqualFold(candidate.Title, query):
			exactAnyYear = append(exactAnyYear, candidate)
		case Normalise(candidate.Title) == normalisedQuery:
			normalised = append(normalised, candidate)
		}
	}

	for _, tier := range [][]Candidate{exactSameYear, exactAnyYear, normalised} {
		if best, ok := mostPopular(tier); ok {
			return best, true
		}
	}
	return Candidate{}, false
}

// mostPopular breaks a tie within one tier.
//
// Only within a tier: popularity across tiers would let a famous remake outrank
// an exact match on the year the folder actually states.
func mostPopular(candidates []Candidate) (Candidate, bool) {
	if len(candidates) == 0 {
		return Candidate{}, false
	}
	best := candidates[0]
	for _, candidate := range candidates[1:] {
		if candidate.Popularity > best.Popularity {
			best = candidate
		}
	}
	return best, true
}

// Normalise reduces a title to what two spellings of the same show share.
//
// Case, punctuation, leading articles and the spacing that punctuation leaves
// behind. Deliberately not more: dropping digits or subtitles would merge
// "Season 2" into "Season", and merging is the one failure that cannot be seen
// from the outside.
func Normalise(title string) string {
	lowered := strings.ToLower(title)
	var builder strings.Builder
	for _, r := range lowered {
		switch {
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			builder.WriteRune(r)
		case unicode.IsSpace(r) || r == '-' || r == ':' || r == '.' || r == '_':
			builder.WriteRune(' ')
		}
	}
	fields := strings.Fields(builder.String())
	if len(fields) > 1 {
		switch fields[0] {
		case "the", "a", "an":
			fields = fields[1:]
		}
	}
	return strings.Join(fields, " ")
}
