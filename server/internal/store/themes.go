package store

import (
	"encoding/json"
	"strings"
)

// Theme collections: films and shows gathered by what they are about —
// immortality, time loops, cop dramas — from the movie database's keywords,
// which the library already carries as tags. A theme matches a title that has
// any of its keywords, and, where it names genres, one of those too.
type Theme struct {
	Slug     string   `json:"Slug"`
	Name     string   `json:"Name"`
	Keywords []string `json:"Keywords"`
	Genres   []string `json:"Genres"`
	Enabled  bool     `json:"Enabled"`
	Custom   bool     `json:"Custom"`
}

// DefaultThemes are the themes Lumiere comes with, all on.
var DefaultThemes = []Theme{
	{Slug: "immortality", Name: "Immortality", Keywords: []string{"immortality", "immortal", "eternal life", "elixir of life", "fountain of youth", "eternal youth"}},
	{Slug: "time-loops", Name: "Time Loops", Keywords: []string{"time loop", "groundhog day", "repeating day", "stuck in time"}},
	{Slug: "time-travel", Name: "Time Travel", Keywords: []string{"time travel", "time machine", "time paradox"}},
	{Slug: "cop-dramas", Name: "Cop Dramas", Keywords: []string{"police procedural", "police", "police officer", "police detective", "cop", "detective", "homicide detective"}, Genres: []string{"Crime"}},
	{Slug: "heists", Name: "Heists", Keywords: []string{"heist", "bank robbery", "robbery", "con artist", "thief"}},
	{Slug: "courtroom", Name: "Courtroom", Keywords: []string{"courtroom", "trial", "lawyer", "legal drama", "attorney"}},
	{Slug: "serial-killers", Name: "Serial Killers", Keywords: []string{"serial killer", "murder investigation"}},
	{Slug: "post-apocalypse", Name: "After the End", Keywords: []string{"post-apocalyptic future", "post-apocalyptic", "apocalypse", "end of the world"}},
	{Slug: "dystopia", Name: "Dystopias", Keywords: []string{"dystopia", "totalitarianism", "authoritarian regime"}},
	{Slug: "artificial-intelligence", Name: "Thinking Machines", Keywords: []string{"artificial intelligence (a.i.)", "artificial intelligence", "android", "robot", "cyborg"}},
	{Slug: "zombies", Name: "Zombies", Keywords: []string{"zombie", "zombie apocalypse", "undead"}},
	{Slug: "vampires", Name: "Vampires", Keywords: []string{"vampire"}},
	{Slug: "revenge", Name: "Revenge", Keywords: []string{"revenge", "vengeance"}},
	{Slug: "survival", Name: "Survival", Keywords: []string{"survival", "stranded", "deserted island"}},
	{Slug: "body-swap", Name: "Body Swaps", Keywords: []string{"body swap", "switching bodies"}},
	{Slug: "isekai", Name: "Another World", Keywords: []string{"isekai", "transported to another world", "reincarnation"}},
	{Slug: "space", Name: "Lost in Space", Keywords: []string{"space travel", "spaceship", "outer space", "space opera"}},
	{Slug: "superheroes", Name: "Superheroes", Keywords: []string{"superhero"}},
	{Slug: "martial-arts", Name: "Martial Arts", Keywords: []string{"martial arts", "kung fu"}},
	{Slug: "haunted", Name: "Haunted", Keywords: []string{"haunted house", "ghost", "haunting"}},
}

const metaThemes = "theme_collections"

// Themes is the built-in list with the owner's changes over it, then the
// themes they added.
func (s *Store) Themes() []Theme {
	raw, _ := s.Meta(metaThemes)
	var saved []Theme
	json.Unmarshal([]byte(raw), &saved)
	bySlug := map[string]Theme{}
	for _, t := range saved {
		bySlug[t.Slug] = t
	}
	var out []Theme
	for _, t := range DefaultThemes {
		t.Enabled = true
		// Only the switch is the owner's: a save sends every theme back
		// whole, and keeping its keywords froze each built-in theme at the
		// day it was saved, so improving one never reached anyone.
		if own, ok := bySlug[t.Slug]; ok {
			t.Enabled = own.Enabled
		}
		out = append(out, t)
	}
	for _, t := range saved {
		if t.Custom {
			out = append(out, t)
		}
	}
	return out
}

// SaveThemes keeps the list as given.
func (s *Store) SaveThemes(themes []Theme) error {
	data, err := json.Marshal(themes)
	if err != nil {
		return err
	}
	return s.SetMeta(metaThemes, string(data))
}

// ThemeMembers lists the films and shows a theme matches.
func (s *Store) ThemeMembers(t Theme) []string {
	if len(t.Keywords) == 0 {
		return nil
	}
	args := []any{}
	marks := make([]string, len(t.Keywords))
	for i, k := range t.Keywords {
		marks[i] = "?"
		args = append(args, strings.ToLower(strings.TrimSpace(k)))
	}
	query := `SELECT DISTINCT i.id FROM item i JOIN item_value v ON v.item_id = i.id
		WHERE i.type IN ('Movie','Series') AND v.kind = 'tag' AND lower(v.value) IN (` + strings.Join(marks, ",") + `)`
	if len(t.Genres) > 0 {
		gm := make([]string, len(t.Genres))
		for i, g := range t.Genres {
			gm[i] = "?"
			args = append(args, strings.ToLower(g))
		}
		query += ` AND EXISTS (SELECT 1 FROM item_value g WHERE g.item_id = i.id AND g.kind = 'genre' AND lower(g.value) IN (` + strings.Join(gm, ",") + `))`
	}
	rows, err := s.DB.Query(query+` ORDER BY COALESCE(i.premiere_date, ''), i.name`, args...)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		out = append(out, id)
	}
	return out
}

// ThemeCollectionFor is the collection made for a theme in one room, if any.
func (s *Store) ThemeCollectionFor(slug string, private bool, rooms LibraryRooms) string {
	rows, err := s.DB.Query(`SELECT i.id, COALESCE(i.library_id, '') FROM item i JOIN item_value v ON v.item_id = i.id
		WHERE i.type = 'BoxSet' AND v.kind = 'theme' AND v.value = ?`, slug)
	if err != nil {
		return ""
	}
	defer rows.Close()
	for rows.Next() {
		var id, lib string
		rows.Scan(&id, &lib)
		if rooms.Private[lib] == private {
			return id
		}
	}
	return ""
}

// ThemeCollections lists every theme collection, for removing a theme's.
func (s *Store) ThemeCollections(slug string) []string {
	rows, err := s.DB.Query(`SELECT item_id FROM item_value WHERE kind = 'theme' AND value = ?`, slug)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		out = append(out, id)
	}
	return out
}

// SyncLinks makes a collection hold exactly these members.
func (s *Store) SyncLinks(id string, members []string) (added, removed int) {
	want := map[string]bool{}
	for _, m := range members {
		want[m] = true
	}
	var gone []string
	for _, m := range s.linkedMembers(id) {
		if !want[m] {
			gone = append(gone, m)
		}
	}
	if len(gone) > 0 {
		s.RemoveLinks(id, gone)
	}
	added, _ = s.AddMissingLinks(id, members)
	return added, len(gone)
}

// AddTags stores movie-database keywords as tags.
func (s *Store) AddTags(id string, tags []string) {
	for _, t := range tags {
		s.DB.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?, 'tag', ?)`, id, t)
	}
}

// UntaggedTitles are films and shows with a movie-database id but no tags,
// not yet asked about.
func (s *Store) UntaggedTitles(limit int) [][3]string {
	rows, err := s.DB.Query(`SELECT i.id, i.type, p.value FROM item i
		JOIN item_value p ON p.item_id = i.id AND p.kind = 'provider:Tmdb'
		WHERE i.type IN ('Movie','Series')
		  AND NOT EXISTS (SELECT 1 FROM item_value t WHERE t.item_id = i.id AND t.kind IN ('tag', 'keywords:checked'))
		LIMIT ?`, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out [][3]string
	for rows.Next() {
		var r [3]string
		rows.Scan(&r[0], &r[1], &r[2])
		out = append(out, r)
	}
	return out
}

// ArtSources are the poster and backdrop files of the first members that
// have them, for a theme collection's artwork.
func (s *Store) ArtSources(members []string, n int) (posters, backdrops []string) {
	for _, m := range members {
		if len(posters) >= n && len(backdrops) >= n {
			break
		}
		var p, b string
		s.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = 'Primary' ORDER BY idx LIMIT 1`, m).Scan(&p)
		s.DB.QueryRow(`SELECT path FROM image WHERE item_id = ? AND kind = 'Backdrop' ORDER BY idx LIMIT 1`, m).Scan(&b)
		if p != "" && len(posters) < n {
			posters = append(posters, p)
		}
		if b != "" && len(backdrops) < n {
			backdrops = append(backdrops, b)
		}
	}
	return posters, backdrops
}
