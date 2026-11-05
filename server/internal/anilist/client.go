package anilist

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Client asks AniList, one request at a time and no faster than its limit.
//
// AniList allows 90 requests a minute and halves that when it is busy; this
// keeps to about 25, and waits as long as a 429 says. Titles are searched
// eight to a request and entries fetched fifty at a time, so a library of a
// thousand anime is a couple of hundred requests.
type Client struct {
	HTTP     *http.Client
	Endpoint string
	Pace     time.Duration
	last     time.Time
}

// NewClient talks to graphql.anilist.co, the one host this package reaches.
func NewClient() *Client {
	return &Client{HTTP: &http.Client{Timeout: 30 * time.Second},
		Endpoint: "https://graphql.anilist.co", Pace: 2400 * time.Millisecond}
}

const fields = `id format startDate { year } title { romaji english native } synonyms coverImage { extraLarge } bannerImage
	relations { edges { relationType(version: 2) node { id type } } }`

type wireMedia struct {
	ID         int `json:"id"`
	Format     string
	StartDate  struct{ Year int } `json:"startDate"`
	Title      struct{ Romaji, English, Native string }
	Synonyms   []string
	CoverImage struct {
		ExtraLarge string `json:"extraLarge"`
	} `json:"coverImage"`
	BannerImage string `json:"bannerImage"`
	Relations   struct {
		Edges []struct {
			RelationType string `json:"relationType"`
			Node         struct {
				ID   int    `json:"id"`
				Type string `json:"type"`
			}
		}
	}
}

func (m wireMedia) node() Node {
	n := Node{ID: m.ID, Romaji: m.Title.Romaji, English: m.Title.English, Native: m.Title.Native,
		Synonyms: m.Synonyms, Year: m.StartDate.Year, Format: m.Format, Cover: m.CoverImage.ExtraLarge,
		Banner: m.BannerImage}
	if n.Banner == "" {
		n.Banner = NoBanner
	}
	for _, e := range m.Relations.Edges {
		n.Relations = append(n.Relations, Edge{ID: e.Node.ID, Kind: e.RelationType, Anime: e.Node.Type == "ANIME"})
	}
	return n
}

// Search looks up several titles at once; results[i] answers titles[i].
func (c *Client) Search(ctx context.Context, titles []string) ([][]Node, error) {
	var q strings.Builder
	vars := map[string]any{}
	q.WriteString("query(")
	for i := range titles {
		if i > 0 {
			q.WriteString(", ")
		}
		fmt.Fprintf(&q, "$s%d: String", i)
		vars["s"+strconv.Itoa(i)] = titles[i]
	}
	q.WriteString(") {")
	for i := range titles {
		fmt.Fprintf(&q, " q%d: Page(perPage: 6) { media(search: $s%d, type: ANIME) { %s } }", i, i, fields)
	}
	q.WriteString(" }")
	var data map[string]struct {
		Media []wireMedia `json:"media"`
	}
	if err := c.post(ctx, q.String(), vars, &data); err != nil {
		return nil, err
	}
	out := make([][]Node, len(titles))
	for i := range titles {
		for _, m := range data["q"+strconv.Itoa(i)].Media {
			out[i] = append(out[i], m.node())
		}
	}
	return out, nil
}

// Fetch reads entries by id, up to fifty.
func (c *Client) Fetch(ctx context.Context, ids []int) ([]Node, error) {
	var data struct {
		Page struct {
			Media []wireMedia `json:"media"`
		} `json:"Page"`
	}
	query := "query($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) { " + fields + " } } }"
	if err := c.post(ctx, query, map[string]any{"ids": ids}, &data); err != nil {
		return nil, err
	}
	var out []Node
	for _, m := range data.Page.Media {
		out = append(out, m.node())
	}
	return out, nil
}

// ErrLimited is AniList saying to slow down for longer than a pass waits.
var ErrLimited = errors.New("anilist: rate limited")

func (c *Client) post(ctx context.Context, query string, vars map[string]any, into any) error {
	for attempt := 0; attempt < 3; attempt++ {
		if wait := c.Pace - time.Since(c.last); wait > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(wait):
			}
		}
		c.last = time.Now()
		body, _ := json.Marshal(map[string]any{"query": query, "variables": vars})
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.Endpoint, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/json")
		resp, err := c.HTTP.Do(req)
		if err != nil {
			// A dropped connection is tried again, at the pace; one blip a
			// minute after the server starts ended a whole pass's lookups.
			if attempt < 2 {
				continue
			}
			return fmt.Errorf("anilist: request failed")
		}
		if resp.StatusCode == http.StatusTooManyRequests {
			resp.Body.Close()
			after, _ := strconv.Atoi(resp.Header.Get("Retry-After"))
			if after <= 0 || after > 120 {
				return ErrLimited
			}
			time.Sleep(time.Duration(after+1) * time.Second)
			continue
		}
		var envelope struct {
			Data   json.RawMessage `json:"data"`
			Errors []struct {
				Message string `json:"message"`
			} `json:"errors"`
		}
		err = json.NewDecoder(resp.Body).Decode(&envelope)
		resp.Body.Close()
		if err != nil {
			return fmt.Errorf("anilist: %s", resp.Status)
		}
		if resp.StatusCode != http.StatusOK && len(envelope.Errors) > 0 {
			return fmt.Errorf("anilist: %s", envelope.Errors[0].Message)
		}
		return json.Unmarshal(envelope.Data, into)
	}
	return ErrLimited
}
