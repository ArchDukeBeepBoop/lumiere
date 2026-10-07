package metadata

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// TMDB is the provider client.
//
// The one place in this server that talks to the outside world besides the
// artwork fetch — and it goes to exactly one host, which is checked on every
// request rather than assumed from the base URL.
type TMDB struct {
	Token string
	HTTP  *http.Client
}

const tmdbHost = "api.themoviedb.org"

// ImageBase is TMDB's CDN, and the host the artwork allowlist already permits.
const ImageBase = "https://image.tmdb.org/t/p/"

func NewTMDB(token string) *TMDB {
	return &TMDB{
		Token: token,
		HTTP: &http.Client{
			Timeout: 20 * time.Second,
			// A redirect off the provider's own host is not a redirect this
			// follows. The allowlist is the boundary and the first hop is not
			// the only one that has to honour it.
			CheckRedirect: func(r *http.Request, via []*http.Request) error {
				if !strings.EqualFold(r.URL.Hostname(), tmdbHost) {
					return fmt.Errorf("redirect off %s", tmdbHost)
				}
				return nil
			},
		},
	}
}

// Details is what a provider knows about one title.
type Details struct {
	ID       string
	Title    string
	Overview string
	Year     int
	Rating   float64
	Genres   []string
	Studios  []string
	// PosterPath and BackdropPath are TMDB's relative paths, to be joined with
	// ImageBase and a size. Kept relative because the size is the caller's
	// decision and baking one in means re-fetching to change it.
	PosterPath   string
	BackdropPath string
	// CollectionID is the film series a film belongs to ("belongs_to_collection"),
	// which is what groups films into collections. Empty for shows.
	CollectionID string
}

// SearchSeries and SearchMovie ask what a title might be.
//
// Adult results are included, deliberately: this is a personal library, and
// TMDB's filter does not warn — it silently omits, so the title being looked up
// is exactly the one that disappears.
func (t *TMDB) SearchSeries(ctx context.Context, title string, year int) ([]Candidate, error) {
	return t.search(ctx, "tv", title, year)
}

func (t *TMDB) SearchMovie(ctx context.Context, title string, year int) ([]Candidate, error) {
	return t.search(ctx, "movie", title, year)
}

func (t *TMDB) search(ctx context.Context, kind, title string, year int) ([]Candidate, error) {
	query := url.Values{
		"query":         {title},
		"include_adult": {"true"},
	}
	if year > 0 {
		// A hint, not a filter: `year` narrows without excluding, and the
		// matcher does the deciding.
		query.Set("year", fmt.Sprint(year))
	}

	var payload struct {
		Results []struct {
			ID           int     `json:"id"`
			Name         string  `json:"name"`
			Title        string  `json:"title"`
			FirstAirDate string  `json:"first_air_date"`
			ReleaseDate  string  `json:"release_date"`
			Popularity   float64 `json:"popularity"`
			Overview     string  `json:"overview"`
			PosterPath   string  `json:"poster_path"`
		} `json:"results"`
	}
	if err := t.get(ctx, "/3/search/"+kind, query, &payload); err != nil {
		return nil, err
	}

	candidates := make([]Candidate, 0, len(payload.Results))
	for _, result := range payload.Results {
		name := result.Name
		if name == "" {
			name = result.Title
		}
		candidates = append(candidates, Candidate{
			ID:         fmt.Sprint(result.ID),
			Title:      name,
			Year:       yearOf(result.FirstAirDate, result.ReleaseDate),
			Popularity: result.Popularity,
			Overview:   result.Overview,
			Poster:     result.PosterPath,
		})
	}
	return candidates, nil
}

// Series and Movie fetch the full record once a match is chosen.
func (t *TMDB) Series(ctx context.Context, id string) (Details, error) {
	return t.details(ctx, "tv", id)
}

func (t *TMDB) Movie(ctx context.Context, id string) (Details, error) {
	return t.details(ctx, "movie", id)
}

func (t *TMDB) details(ctx context.Context, kind, id string) (Details, error) {
	var payload struct {
		ID           int     `json:"id"`
		Name         string  `json:"name"`
		Title        string  `json:"title"`
		Overview     string  `json:"overview"`
		FirstAirDate string  `json:"first_air_date"`
		ReleaseDate  string  `json:"release_date"`
		VoteAverage  float64 `json:"vote_average"`
		PosterPath   string  `json:"poster_path"`
		BackdropPath string  `json:"backdrop_path"`
		Genres       []struct {
			Name string `json:"name"`
		} `json:"genres"`
		Networks []struct {
			Name string `json:"name"`
		} `json:"networks"`
		Companies []struct {
			Name string `json:"name"`
		} `json:"production_companies"`
		Collection *struct {
			ID int `json:"id"`
		} `json:"belongs_to_collection"`
	}
	if err := t.get(ctx, "/3/"+kind+"/"+id, nil, &payload); err != nil {
		return Details{}, err
	}

	details := Details{
		ID:           fmt.Sprint(payload.ID),
		Title:        payload.Name,
		Overview:     payload.Overview,
		Year:         yearOf(payload.FirstAirDate, payload.ReleaseDate),
		Rating:       payload.VoteAverage,
		PosterPath:   payload.PosterPath,
		BackdropPath: payload.BackdropPath,
	}
	if details.Title == "" {
		details.Title = payload.Title
	}
	if payload.Collection != nil && payload.Collection.ID > 0 {
		details.CollectionID = fmt.Sprint(payload.Collection.ID)
	}
	for _, genre := range payload.Genres {
		details.Genres = append(details.Genres, genre.Name)
	}
	// Networks for a show, production companies for a film — the same field to
	// anyone reading a library, and only one of them is ever populated.
	for _, network := range payload.Networks {
		details.Studios = append(details.Studios, network.Name)
	}
	for _, company := range payload.Companies {
		details.Studios = append(details.Studios, company.Name)
	}
	return details, nil
}

func (t *TMDB) get(ctx context.Context, path string, query url.Values, into any) error {
	endpoint := url.URL{Scheme: "https", Host: tmdbHost, Path: path}
	if query != nil {
		endpoint.RawQuery = query.Encode()
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return err
	}
	// The v4 read token, hence Bearer. The v3 key goes in a query parameter and
	// is not interchangeable — the commonest mistake with this API.
	request.Header.Set("Authorization", "Bearer "+t.Token)
	request.Header.Set("Accept", "application/json")

	response, err := t.HTTP.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("tmdb %s: %s", path, response.Status)
	}
	return json.NewDecoder(response.Body).Decode(into)
}

// yearOf reads the first four digits of whichever date the payload carried.
func yearOf(dates ...string) int {
	for _, date := range dates {
		if len(date) >= 4 {
			var year int
			if _, err := fmt.Sscanf(date[:4], "%d", &year); err == nil && year > 1800 {
				return year
			}
		}
	}
	return 0
}

// RemoteImage is one piece of artwork a provider offers.
type RemoteImage struct {
	URL      string
	Thumb    string
	Kind     string
	Width    int
	Height   int
	Language string
	Rating   float64
}

// Images lists everything TMDB has for a title.
//
// Both posters and backdrops in one request, because the picker offers a type
// and switching between them should not cost a round trip.
func (t *TMDB) Images(ctx context.Context, kind, id string) ([]RemoteImage, error) {
	var payload struct {
		Posters   []tmdbImage `json:"posters"`
		Backdrops []tmdbImage `json:"backdrops"`
		Stills    []tmdbImage `json:"stills"`
	}
	// `include_image_language=null` is what returns the textless artwork most
	// people actually want alongside the localised ones.
	query := url.Values{"include_image_language": {"en,null"}}
	if err := t.get(ctx, "/3/"+kind+"/"+id+"/images", query, &payload); err != nil {
		return nil, err
	}

	var images []RemoteImage
	add := func(list []tmdbImage, name string) {
		for _, image := range list {
			images = append(images, RemoteImage{
				// The full-size original for what gets stored, and a small one
				// for the grid: a picker showing thirty 2000px posters is
				// thirty full downloads to draw thumbnails.
				URL:      ImageBase + "original" + image.FilePath,
				Thumb:    ImageBase + "w342" + image.FilePath,
				Kind:     name,
				Width:    image.Width,
				Height:   image.Height,
				Language: image.Language,
				Rating:   image.VoteAverage,
			})
		}
	}
	add(payload.Posters, "Primary")
	add(payload.Backdrops, "Backdrop")
	add(payload.Stills, "Primary")
	return images, nil
}

type tmdbImage struct {
	FilePath    string  `json:"file_path"`
	Width       int     `json:"width"`
	Height      int     `json:"height"`
	Language    string  `json:"iso_639_1"`
	VoteAverage float64 `json:"vote_average"`
}
