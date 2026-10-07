package metadata

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

// Credits: who is in it, and who made it.
//
// The Jellyfin import brought a cast for everything it had seen; the naming
// pass, which took over from it, named a film and gave it a poster and left
// its Cast & Crew row empty — a film that arrived after the last import had
// nobody in it. TMDB lists the cast and crew for the same id the pass already
// matched, one request per title.

// Credit is one line of a title's credits, as TMDB gives it.
type Credit struct {
	TmdbID      int
	Name        string
	Role        string // the character, or the job
	Type        string // Jellyfin's: Actor, Director, Writer, Producer
	Order       int
	ProfilePath string
}

// maxCast is how many faces one title keeps. TMDB lists every extra; the row
// is for the people you might recognise.
const maxCast = 30

// crewJobs maps the jobs worth a credit to Jellyfin's person types.
var crewJobs = map[string]string{
	"Director": "Director", "Writer": "Writer", "Screenplay": "Writer",
	"Story": "Writer", "Novel": "Writer", "Producer": "Producer",
	"Executive Producer": "Producer", "Creator": "Writer",
}

// Credits fetches a title's cast and crew. A film's from its credits; a show's
// from its aggregate credits, which span every season rather than one.
func (t *TMDB) Credits(ctx context.Context, series bool, id string) ([]Credit, error) {
	var payload struct {
		Cast []struct {
			ID          int    `json:"id"`
			Name        string `json:"name"`
			Character   string `json:"character"`
			Order       int    `json:"order"`
			ProfilePath string `json:"profile_path"`
			Roles       []struct {
				Character string `json:"character"`
			} `json:"roles"`
		} `json:"cast"`
		Crew []struct {
			ID          int    `json:"id"`
			Name        string `json:"name"`
			Job         string `json:"job"`
			ProfilePath string `json:"profile_path"`
			Jobs        []struct {
				Job string `json:"job"`
			} `json:"jobs"`
		} `json:"crew"`
	}
	path := "/3/movie/" + id + "/credits"
	if series {
		path = "/3/tv/" + id + "/aggregate_credits"
	}
	if err := t.get(ctx, path, nil, &payload); err != nil {
		return nil, err
	}

	var out []Credit
	for i, c := range payload.Cast {
		if i >= maxCast {
			break
		}
		role := c.Character
		if role == "" && len(c.Roles) > 0 {
			role = c.Roles[0].Character
		}
		out = append(out, Credit{
			TmdbID: c.ID, Name: c.Name, Role: role, Type: "Actor",
			Order: c.Order, ProfilePath: c.ProfilePath,
		})
	}
	seen := map[string]bool{}
	for _, c := range payload.Crew {
		jobs := []string{c.Job}
		for _, j := range c.Jobs {
			jobs = append(jobs, j.Job)
		}
		for _, job := range jobs {
			kind, wanted := crewJobs[job]
			key := fmt.Sprint(c.ID, "/", kind)
			if !wanted || seen[key] {
				continue
			}
			seen[key] = true
			out = append(out, Credit{
				TmdbID: c.ID, Name: c.Name, Role: job, Type: kind,
				Order: maxCast + len(out), ProfilePath: c.ProfilePath,
			})
		}
	}
	return out, nil
}

// PendingCredits lists matched titles with no credits at all.
func (e *Enricher) PendingCredits(limit int) ([]Pending, error) {
	rows, err := e.Store.DB.Query(`
		SELECT i.id, i.type, i.name, COALESCE(i.production_year, 0), v.value
		FROM item i
		JOIN item_value v ON v.item_id = i.id AND v.kind = 'provider:Tmdb'
		WHERE i.type IN ('Movie', 'Series')
		  AND NOT EXISTS (SELECT 1 FROM person p WHERE p.item_id = i.id)
		  AND NOT EXISTS (
			SELECT 1 FROM item_value asked WHERE asked.item_id = i.id AND asked.kind = 'credits:asked'
		  )
		ORDER BY i.date_created DESC
		LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Pending
	for rows.Next() {
		var p Pending
		if err := rows.Scan(&p.ID, &p.Type, &p.Name, &p.Year, &p.TmdbID); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Credit fetches and files one title's credits. Returns how many were kept.
//
// A person keeps the id an earlier import gave them, matched by name, so the
// cast of a new film joins the same person page — and the same portrait — as
// the cast of an old one. A person the library has never seen gets an id
// from their TMDB id, stable across runs.
func (e *Enricher) Credit(ctx context.Context, item Pending, series bool) (int, error) {
	credits, err := e.TMDB.Credits(ctx, series, item.TmdbID)
	if err != nil {
		return 0, err
	}
	if _, err := e.Store.DB.Exec(`
		INSERT INTO item_value (item_id, kind, value) VALUES (?, 'credits:asked', ?)
		ON CONFLICT DO NOTHING`, item.ID, time.Now().UTC().Format(time.RFC3339)); err != nil {
		return 0, err
	}

	kept := 0
	for _, c := range credits {
		personID, err := e.personID(c)
		if err != nil {
			return kept, err
		}
		if _, err := e.Store.DB.Exec(`
			INSERT INTO person (item_id, person_id, name, role, type, sort_order)
			VALUES (?,?,?,?,?,?)
			ON CONFLICT(item_id, person_id, type, role) DO NOTHING`,
			item.ID, personID, c.Name, c.Role, c.Type, c.Order); err != nil {
			return kept, err
		}
		kept++
		// A face for the row, where the person has none yet. Cast only: a
		// producer's portrait is a request spent on a cell nobody looks at.
		if c.Type != "Actor" || c.ProfilePath == "" {
			continue
		}
		var has int
		e.Store.DB.QueryRow(`SELECT count(*) FROM image WHERE item_id = ? AND kind = 'Primary'`, personID).Scan(&has)
		if has > 0 {
			continue
		}
		if err := e.fetchImage(personID, "Primary", "w185"+c.ProfilePath); err != nil {
			e.Log.Info("metadata: portrait not fetched", "person", c.Name, "reason", err)
		}
	}
	return kept, nil
}

// personID is the id a credit is filed under: the one the library already
// has for that name, else one made from the TMDB id.
func (e *Enricher) personID(c Credit) (string, error) {
	var existing string
	err := e.Store.DB.QueryRow(
		`SELECT person_id FROM person WHERE name = ? LIMIT 1`, c.Name).Scan(&existing)
	if err == nil && existing != "" {
		return existing, nil
	}
	sum := sha256.Sum256([]byte(fmt.Sprintf("tmdb-person:%d", c.TmdbID)))
	return hex.EncodeToString(sum[:16]), nil
}
