package api

import (
	"fmt"
	"net/http"
	"sort"
	"strings"

	"lumiere-server/internal/store"
)

// Ideas for smart collections, made from what this library holds — the way
// Netflix names its micro-genres from a template ("Japanese Science
// Fiction") and offers only the ones with enough titles behind them.

// minIdea and maxIdea bound what is offered: fewer than eight is a list,
// not a shelf, and more than 150 is a library again ("Japanese Animation",
// 500 titles, says nothing the Anime library does not).
const (
	minIdea = 8
	maxIdea = 150
)

// demonyms name a country as an adjective, for idea names. A country not
// here is offered by its code's name in the app instead, as "Films from …".
var demonyms = map[string]string{
	"JP": "Japanese", "KR": "Korean", "US": "American", "GB": "British", "FR": "French",
	"CN": "Chinese", "HK": "Hong Kong", "TW": "Taiwanese", "IN": "Indian", "ES": "Spanish",
	"IT": "Italian", "DE": "German", "TH": "Thai", "MX": "Mexican", "CA": "Canadian",
	"AU": "Australian", "SE": "Swedish", "DK": "Danish", "NO": "Norwegian", "RU": "Russian",
	"BR": "Brazilian", "IE": "Irish", "NZ": "New Zealand", "BE": "Belgian", "AR": "Argentine",
}

type smartIdea struct {
	Name  string
	Rules store.SmartRules
	Count int
}

// SmartIdeas is GET /Lumiere/SmartCollections/Ideas.
func (h CollectionSuggestHandler) SmartIdeas(w http.ResponseWriter, r *http.Request) {
	private := h.privateFolders()
	taken := map[string]bool{}
	rows, _ := h.Store.DB.Query(`SELECT lower(name) FROM item WHERE type = 'BoxSet'`)
	for rows != nil && rows.Next() {
		var n string
		rows.Scan(&n)
		taken[n] = true
	}
	if rows != nil {
		rows.Close()
	}
	var ideas []smartIdea
	offer := func(name string, rules ...store.SmartRule) {
		if taken[strings.ToLower(name)] {
			return
		}
		set := store.SmartRules{Rules: rules}
		members, err := h.Store.SmartMembers(set, private)
		if err == nil && len(members) >= minIdea && len(members) <= maxIdea {
			ideas = append(ideas, smartIdea{name, set, len(members)})
		}
	}
	genres := h.topValues("genre", 14)
	for _, country := range h.topValues("country", 8) {
		adjective, ok := demonyms[country]
		if !ok {
			continue
		}
		for _, genre := range genres {
			offer(adjective+" "+genre, store.SmartRule{Field: "country", Op: "is", Value: country},
				store.SmartRule{Field: "genre", Op: "is", Value: genre})
		}
	}
	for decade := 1960; decade <= 2010; decade += 10 {
		for _, genre := range genres[:min(6, len(genres))] {
			label := fmt.Sprintf("%02ds", decade%100)
			if decade >= 2000 {
				label = fmt.Sprintf("%ds", decade)
			}
			offer(label+" "+genre,
				store.SmartRule{Field: "year", Op: "≥", Value: fmt.Sprint(decade)},
				store.SmartRule{Field: "year", Op: "≤", Value: fmt.Sprint(decade + 9)},
				store.SmartRule{Field: "genre", Op: "is", Value: genre})
		}
	}
	offer("Highly Rated, Not Yet Watched", store.SmartRule{Field: "rating", Op: "≥", Value: "8"},
		store.SmartRule{Field: "watched", Op: "is", Value: "false"})
	offer("Under 90 Minutes", store.SmartRule{Field: "type", Op: "is", Value: "Movie"},
		store.SmartRule{Field: "runtime", Op: "≤", Value: "90"})
	offer("Added This Month", store.SmartRule{Field: "added", Op: "within days", Value: "30"})
	// The more specific first, within the bounds: a 40-title shelf is a
	// discovery, a 140-title one is closer to a browse.
	sort.Slice(ideas, func(i, j int) bool { return ideas[i].Count < ideas[j].Count })
	writeJSON(w, http.StatusOK, map[string]any{"Items": ideas[:min(30, len(ideas))]})
}

// SmartChoices is GET /Lumiere/SmartCollections/Choices: what each field
// can be set to, from what the library actually holds.
func (h CollectionSuggestHandler) SmartChoices(w http.ResponseWriter, r *http.Request) {
	type library struct{ Id, Name string }
	var libraries []library
	libs, _ := h.Store.ListLibraries()
	for _, l := range libs {
		if l.Kind != "music" && l.Kind != "boxsets" && l.Kind != "playlists" {
			libraries = append(libraries, library{l.ID, l.Name})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"Fields":    store.SmartFields,
		"Genres":    h.topValues("genre", 80),
		"Countries": h.topValues("country", 80),
		"Keywords":  h.topValues("tag", 400),
		"Studios":   h.topValues("studio", 200),
		"Libraries": libraries,
	})
}

// topValues is a value kind's most common values on films and shows.
func (h CollectionSuggestHandler) topValues(kind string, limit int) []string {
	rows, err := h.Store.DB.Query(`SELECT v.value FROM item_value v JOIN item i ON i.id = v.item_id
		WHERE v.kind = ? AND i.type IN ('Movie', 'Series')
		GROUP BY v.value ORDER BY count(*) DESC LIMIT ?`, kind, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var v string
		rows.Scan(&v)
		out = append(out, v)
	}
	return out
}
