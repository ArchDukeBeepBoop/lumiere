package metadata

import (
	"context"
	"fmt"
	"net/url"
	"strings"
)

// A film series as the movie database lists it: its name and every film in
// it, so a collection can say which ones this library is missing.
type TMDBCollection struct {
	ID           string
	Name         string
	Overview     string
	PosterPath   string
	BackdropPath string
	Parts        []TMDBPart
}

type TMDBPart struct {
	ID    string
	Title string
	Year  int
}

func (t *TMDB) Collection(ctx context.Context, id string) (TMDBCollection, error) {
	var payload struct {
		ID           int    `json:"id"`
		Name         string `json:"name"`
		Overview     string `json:"overview"`
		PosterPath   string `json:"poster_path"`
		BackdropPath string `json:"backdrop_path"`
		Parts        []struct {
			ID          int    `json:"id"`
			Title       string `json:"title"`
			ReleaseDate string `json:"release_date"`
		} `json:"parts"`
	}
	if err := t.get(ctx, "/3/collection/"+id, nil, &payload); err != nil {
		return TMDBCollection{}, err
	}
	out := TMDBCollection{ID: fmt.Sprint(payload.ID), Name: payload.Name, Overview: payload.Overview,
		PosterPath: payload.PosterPath, BackdropPath: payload.BackdropPath}
	for _, p := range payload.Parts {
		out.Parts = append(out.Parts, TMDBPart{ID: fmt.Sprint(p.ID), Title: p.Title, Year: yearOf(p.ReleaseDate)})
	}
	return out, nil
}

// SearchCollection finds a film series by name. Only an exact match on the
// name, ignoring case and a trailing "Collection", is returned — a near
// match fills a collection with the wrong films.
func (t *TMDB) SearchCollection(ctx context.Context, name string) (string, error) {
	results, err := t.SearchCollections(ctx, name)
	if err != nil {
		return "", err
	}
	for _, r := range results {
		if strings.EqualFold(bareCollectionName(r.Name), bareCollectionName(name)) {
			return r.ID, nil
		}
	}
	return "", nil
}

// CollectionMatch is one search result: a series id and its name.
// CollectionMatch is one search result. Poster is a full image URL, for the
// discovery sheet; empty where the database has none.
type CollectionMatch struct{ ID, Name, Overview, Poster string }

// SearchCollections lists the film series a name finds, best first, for a
// person to choose from when no exact name matched.
func (t *TMDB) SearchCollections(ctx context.Context, name string) ([]CollectionMatch, error) {
	var payload struct {
		Results []struct {
			ID         int    `json:"id"`
			Name       string `json:"name"`
			Overview   string `json:"overview"`
			PosterPath string `json:"poster_path"`
		} `json:"results"`
	}
	q := url.Values{"query": {bareCollectionName(name)}}
	if err := t.get(ctx, "/3/search/collection", q, &payload); err != nil {
		return nil, err
	}
	var out []CollectionMatch
	for _, r := range payload.Results {
		poster := ""
		if r.PosterPath != "" {
			poster = ImageBase + "w342" + r.PosterPath
		}
		out = append(out, CollectionMatch{ID: fmt.Sprint(r.ID), Name: r.Name, Overview: r.Overview, Poster: poster})
	}
	return out, nil
}

func bareCollectionName(n string) string {
	n = strings.TrimSpace(n)
	lower := strings.ToLower(n)
	if strings.HasSuffix(lower, " collection") {
		n = n[:len(n)-len(" collection")]
	}
	return strings.TrimSpace(n)
}
