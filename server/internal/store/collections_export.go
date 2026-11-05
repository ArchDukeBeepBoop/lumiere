package store

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Collections, written down beside every backup in a form that outlives the
// database.
//
// On 2026-10-25 the database and its backups went together, and the library
// was rebuilt from the Mac app's cache — which knew every collection's name
// and count but not one of its members, because membership never left the
// server. The collections made by hand were lost. This file is what would have
// saved them: each collection, what made it (by hand, a theme, a TMDB film
// series) and its members by TMDB id, file path, name and year, so they can be
// matched back onto a library rebuilt with new ids. Plain JSON, readable
// without Lumiere. See ImportCollections.

// ExportedCollection is one collection as written to collections.json.
type ExportedCollection struct {
	Name     string           `json:"Name"`
	Kind     string           `json:"Kind"` // manual, theme, tmdb, playlist
	Overview string           `json:"Overview,omitempty"`
	Members  []ExportedMember `json:"Members"`
}

// ExportedMember identifies a title every way a rebuilt library could know it.
type ExportedMember struct {
	Name   string `json:"Name"`
	Year   int    `json:"Year,omitempty"`
	Type   string `json:"Type"`
	TmdbID string `json:"TmdbId,omitempty"`
	Path   string `json:"Path,omitempty"`
}

// ExportCollections reads every collection and playlist with its members.
func (s *Store) ExportCollections() ([]ExportedCollection, error) {
	rows, err := s.DB.Query(`
		SELECT b.id, b.type, b.name, COALESCE(b.overview, ''),
		  CASE WHEN b.type = 'Playlist' THEN 'playlist'
		       WHEN EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = b.id AND v.kind = 'theme') THEN 'theme'
		       WHEN EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = b.id AND v.kind = 'anilist:franchise') THEN 'anilist'
		       WHEN EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = b.id AND v.kind = 'smart:rules') THEN 'smart'
		       WHEN EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = b.id
		                    AND v.kind IN ('tmdb_collection', 'auto:collection', 'provider:TmdbCollection')) THEN 'tmdb'
		       ELSE 'manual' END
		FROM item b WHERE b.type IN ('BoxSet', 'Playlist') ORDER BY b.name COLLATE NOCASE`)
	if err != nil {
		return nil, err
	}
	type head struct {
		id, kind string
		c        ExportedCollection
	}
	var heads []head
	for rows.Next() {
		var h head
		var typ string
		if err := rows.Scan(&h.id, &typ, &h.c.Name, &h.c.Overview, &h.kind); err != nil {
			rows.Close()
			return nil, err
		}
		h.c.Kind = h.kind
		heads = append(heads, h)
	}
	rows.Close()
	out := make([]ExportedCollection, 0, len(heads))
	for _, h := range heads {
		members, err := s.exportMembers(h.id)
		if err != nil {
			return nil, err
		}
		h.c.Members = members
		out = append(out, h.c)
	}
	return out, nil
}

func (s *Store) exportMembers(id string) ([]ExportedMember, error) {
	rows, err := s.DB.Query(`
		SELECT i.name, COALESCE(i.production_year, 0), i.type, COALESCE(i.path, ''),
		       COALESCE((SELECT v.value FROM item_value v WHERE v.item_id = i.id AND v.kind = 'provider:Tmdb' LIMIT 1), '')
		FROM link l JOIN item i ON i.id = l.child_id
		WHERE l.parent_id = ? ORDER BY l.position`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ExportedMember
	for rows.Next() {
		var m ExportedMember
		if err := rows.Scan(&m.Name, &m.Year, &m.Type, &m.Path, &m.TmdbID); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// WriteCollectionsExport writes collections-<date>.json into dir and keeps
// the newest fourteen. Returns the path written.
func (s *Store) WriteCollectionsExport(dir string) (string, error) {
	all, err := s.ExportCollections()
	if err != nil {
		return "", err
	}
	data, err := json.MarshalIndent(struct {
		Written     string               `json:"Written"`
		Collections []ExportedCollection `json:"Collections"`
	}{time.Now().UTC().Format(time.RFC3339), all}, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "collections-"+time.Now().Format("20060102")+".json")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return "", err
	}
	entries, _ := os.ReadDir(dir)
	var exports []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "collections-") && strings.HasSuffix(e.Name(), ".json") {
			exports = append(exports, e.Name())
		}
	}
	sort.Strings(exports)
	for len(exports) > 14 {
		os.Remove(filepath.Join(dir, exports[0]))
		exports = exports[1:]
	}
	return path, nil
}

// ImportCollections puts back the hand-made collections and playlists from an
// export that the library does not have by name. Themes and TMDB series are
// left to rebuild themselves. Members are matched by TMDB id, then path, then
// name and year. Returns collections made and members matched.
func (s *Store) ImportCollections(path string) (made, matched int, err error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, 0, err
	}
	var file struct {
		Collections []ExportedCollection `json:"Collections"`
	}
	if err := json.Unmarshal(data, &file); err != nil {
		return 0, 0, err
	}
	for _, c := range file.Collections {
		if c.Kind != "manual" && c.Kind != "playlist" {
			continue
		}
		kind := "BoxSet"
		if c.Kind == "playlist" {
			kind = "Playlist"
		}
		var exists int
		s.DB.QueryRow(`SELECT count(*) FROM item WHERE type = ? AND name = ?`, kind, c.Name).Scan(&exists)
		if exists > 0 {
			continue
		}
		var ids []string
		for _, m := range c.Members {
			if id := s.matchMember(m); id != "" {
				ids = append(ids, id)
			}
		}
		if _, err := s.CreateContainer(kind, c.Name, ids); err != nil {
			return made, matched, err
		}
		made++
		matched += len(ids)
	}
	return made, matched, nil
}

func (s *Store) matchMember(m ExportedMember) string {
	var id string
	try := func(query string, args ...any) bool {
		err := s.DB.QueryRow(query, args...).Scan(&id)
		return err == nil && id != ""
	}
	if m.TmdbID != "" && try(`SELECT i.id FROM item i JOIN item_value v ON v.item_id = i.id
		WHERE v.kind = 'provider:Tmdb' AND v.value = ? AND i.type = ? LIMIT 1`, m.TmdbID, m.Type) {
		return id
	}
	if m.Path != "" && try(`SELECT id FROM item WHERE path = ? LIMIT 1`, m.Path) {
		return id
	}
	if try(`SELECT id FROM item WHERE type = ? AND name = ? COLLATE NOCASE
		AND (? = 0 OR production_year = ?) LIMIT 1`, m.Type, m.Name, m.Year, m.Year) {
		return id
	}
	return ""
}
