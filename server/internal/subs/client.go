// Package subs finds and fetches subtitles for a file that has none.
//
// OpenSubtitles is the provider: it is the only one with an open API, a
// catalogue that covers anime as well as film, and terms that permit a
// personal server to use it. The key is the user's own — stored beside the
// database like the provider key, never in the source — and without one this
// package does nothing at all, which is the honest state for a feature that
// depends on somebody else's account.
package subs

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const api = "https://api.opensubtitles.com/api/v1"

// ErrNoKey is "the server has no OpenSubtitles key", which is a thing to say
// to the user rather than an error to log.
var ErrNoKey = errors.New("no subtitle provider key")

// Client talks to OpenSubtitles.
type Client struct {
	Key string
	// Agent identifies this app to the provider, which their terms require.
	Agent string
	HTTP  *http.Client
	// Remaining is how many downloads the provider says are left today, as of
	// the last Download; -1 before any. The queue stops for the day at 0.
	Remaining int
	// token is the login token, where a username and password were given.
	// Downloads without one are capped at a handful a day.
	token string
}

func New(key string) *Client {
	return &Client{
		Key:       key,
		Agent:     "Lumiere v1",
		Remaining: -1,
		HTTP:      &http.Client{Timeout: 30 * time.Second},
	}
}

// Candidate is one subtitle the provider offers.
type Candidate struct {
	FileID    int     `json:"FileId"`
	Release   string  `json:"Release"`
	Language  string  `json:"Language"`
	Downloads int     `json:"Downloads"`
	Rating    float64 `json:"Rating"`
	FromTrust bool    `json:"FromTrusted"`
	HearingIm bool    `json:"HearingImpaired"`
	// MachineTranslated and AiTranslated are worth showing: both read badly,
	// and a list that hides them is a list that recommends them.
	Machine bool `json:"MachineTranslated"`
	AI      bool `json:"AiTranslated"`
	FPS     float64
	Format  string `json:"Format"`
}

// Query is what to look for.
type Query struct {
	Title    string
	Season   int
	Episode  int
	Year     int
	Language string
	// TmdbID narrows to one title where the library knows it, which is worth
	// far more than the words in a filename.
	TmdbID string
	// Filename is the release name, which OpenSubtitles matches against its
	// own release names — the closest thing to a hash match without one.
	Filename string
}

// Search asks the provider what it has.
func (c *Client) Search(ctx context.Context, q Query) ([]Candidate, error) {
	if c.Key == "" {
		return nil, ErrNoKey
	}
	values := url.Values{}
	if q.TmdbID != "" {
		if q.Season > 0 || q.Episode > 0 {
			values.Set("parent_tmdb_id", q.TmdbID)
		} else {
			values.Set("tmdb_id", q.TmdbID)
		}
	}
	if q.Title != "" {
		values.Set("query", q.Title)
	}
	if q.Season > 0 {
		values.Set("season_number", strconv.Itoa(q.Season))
	}
	if q.Episode > 0 {
		values.Set("episode_number", strconv.Itoa(q.Episode))
	}
	if q.Year > 0 && q.Season == 0 {
		values.Set("year", strconv.Itoa(q.Year))
	}
	language := q.Language
	if language == "" {
		language = "en"
	}
	values.Set("languages", language)

	var payload struct {
		Data []struct {
			Attributes struct {
				Release          string  `json:"release"`
				Language         string  `json:"language"`
				DownloadCount    int     `json:"download_count"`
				Ratings          float64 `json:"ratings"`
				FromTrusted      bool    `json:"from_trusted"`
				HearingImpaired  bool    `json:"hearing_impaired"`
				MachineTranslate bool    `json:"machine_translated"`
				AITranslated     bool    `json:"ai_translated"`
				FPS              float64 `json:"fps"`
				Files            []struct {
					FileID   int    `json:"file_id"`
					FileName string `json:"file_name"`
				} `json:"files"`
			} `json:"attributes"`
		} `json:"data"`
	}
	if err := c.get(ctx, "/subtitles?"+values.Encode(), &payload); err != nil {
		return nil, err
	}

	var out []Candidate
	for _, row := range payload.Data {
		a := row.Attributes
		if len(a.Files) == 0 {
			continue
		}
		out = append(out, Candidate{
			FileID: a.Files[0].FileID, Release: a.Release, Language: a.Language,
			Downloads: a.DownloadCount, Rating: a.Ratings, FromTrust: a.FromTrusted,
			HearingIm: a.HearingImpaired, Machine: a.MachineTranslate, AI: a.AITranslated,
			FPS: a.FPS, Format: strings.ToLower(extensionOf(a.Files[0].FileName)),
		})
	}
	return out, nil
}

// Download resolves a file id to the subtitle's text.
//
// Two calls, as the provider requires: one asks for a link and spends a unit
// of the day's quota, the other fetches it. The quota is why nothing here
// downloads speculatively — a search is free, a download is not.
func (c *Client) Download(ctx context.Context, fileID int) ([]byte, string, error) {
	if c.Key == "" {
		return nil, "", ErrNoKey
	}
	body, _ := json.Marshal(map[string]any{"file_id": fileID})
	var link struct {
		Link     string `json:"link"`
		FileName string `json:"file_name"`
		Message  string `json:"message"`
		Requests int    `json:"requests"`
		Remain   int    `json:"remaining"`
	}
	if err := c.post(ctx, "/download", body, &link); err != nil {
		return nil, "", err
	}
	c.Remaining = link.Remain
	if link.Link == "" {
		return nil, "", fmt.Errorf("provider offered no link: %s", link.Message)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, link.Link, nil)
	if err != nil {
		return nil, "", err
	}
	response, err := c.HTTP.Do(request)
	if err != nil {
		return nil, "", err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("download: %s", response.Status)
	}
	// Capped: an unbounded read from a remote host is a memory budget
	// somebody else controls. A subtitle for a long film is under a megabyte.
	text, err := io.ReadAll(io.LimitReader(response.Body, 8<<20))
	if err != nil {
		return nil, "", err
	}
	return text, extensionOf(link.FileName), nil
}

func (c *Client) get(ctx context.Context, path string, into any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, api+path, nil)
	if err != nil {
		return err
	}
	return c.do(request, into)
}

func (c *Client) post(ctx context.Context, path string, body []byte, into any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, api+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	return c.do(request, into)
}

func (c *Client) do(request *http.Request, into any) error {
	request.Header.Set("Api-Key", c.Key)
	request.Header.Set("User-Agent", c.Agent)
	request.Header.Set("Accept", "application/json")
	if c.token != "" {
		request.Header.Set("Authorization", "Bearer "+c.token)
	}
	response, err := c.HTTP.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		detail, _ := io.ReadAll(io.LimitReader(response.Body, 2<<10))
		return fmt.Errorf("opensubtitles: %s: %s", response.Status, strings.TrimSpace(string(detail)))
	}
	return json.NewDecoder(io.LimitReader(response.Body, 8<<20)).Decode(into)
}

func extensionOf(name string) string {
	if i := strings.LastIndex(name, "."); i >= 0 && i < len(name)-1 {
		return strings.ToLower(name[i+1:])
	}
	return "srt"
}
