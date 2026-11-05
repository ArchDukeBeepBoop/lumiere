package store

import (
	"encoding/json"
	"sort"
	"strings"
)

// A music library's artists.
//
// Artists are filed under no library: the scan makes one per name it reads
// in a tag, and the import left Jellyfin's the same way. So asking for the
// artists *in* a library — the Artists tab, which always asks with the
// library as parent — matched nothing at all, and the tab stood empty over
// 1,088 artists. An artist is in a library when one of its albums or tracks
// credits them.

// artistsOfLibrary says whether this is that question.
func (q Query) artistsOfLibrary() bool {
	return q.ParentID != "" && len(q.Types) == 1 && q.Types[0] == "MusicArtist"
}

// artistLists works out, once per request, the two lists the artist clauses
// take as JSON: the names a library credits, and the duplicate rows to drop.
func (s *Store) artistLists(q *Query) error {
	var err error
	if q.artistsOfLibrary() {
		if q.credited, err = s.creditedArtists(append([]string{q.ParentID}, q.FolderIDs...)); err != nil {
			return err
		}
	}
	if q.OneArtistPerName {
		q.dropped, err = s.duplicateArtists()
	}
	return err
}

// artistsInLibrary is the clause: filed in the library, or named by one of
// its albums or tracks. The names are worked out once, in Go, by
// creditedArtists and passed in as a JSON list.
//
// It used to be a correlated subquery — for every artist, every album and
// track searched with instr() — 1,088 artists by 3,300 rows, run twice (once
// more for the total). 3.6 s on a quiet library and up to 48 s beside an
// artwork pass, so every device gave up on the Artists tab before it filled.
func (q Query) artistsInLibrary() (string, []any) {
	ids := append([]string{q.ParentID}, q.FolderIDs...)
	args := make([]any, 0, len(ids)+1)
	for _, id := range ids {
		args = append(args, id)
	}
	names, _ := json.Marshal(append([]string{}, q.credited...)) // never "null"; see dropped
	args = append(args, string(names))
	return `(i.library_id IN (` + placeholders(len(ids)) + `)
		OR lower(i.name) IN (SELECT value FROM json_each(?)))`, args
}

// creditedArtists is every artist name a library's albums and tracks carry,
// lowercased: album artist and artist tags, split the way the scanner splits
// them when it makes the artists in the first place.
func (s *Store) creditedArtists(libraryIDs []string) ([]string, error) {
	args := make([]any, len(libraryIDs))
	for i, id := range libraryIDs {
		args[i] = id
	}
	rows, err := s.DB.Query(`SELECT COALESCE(album_artist, ''), COALESCE(artists, '') FROM item
		WHERE library_id IN (`+placeholders(len(libraryIDs))+`) AND type IN ('Audio', 'MusicAlbum')`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	seen := map[string]bool{}
	for rows.Next() {
		var albumArtist, artists string
		if err := rows.Scan(&albumArtist, &artists); err != nil {
			return nil, err
		}
		for _, name := range creditNames(albumArtist, artists) {
			seen[name] = true
		}
	}
	out := make([]string, 0, len(seen))
	for name := range seen {
		out = append(out, name)
	}
	sort.Strings(out)
	return out, rows.Err()
}

// creditNames is the lowercased, de-duplicated names in a row's artist tags.
// ";", "/" and "|" separate names, as in scanner.splitArtists — and the whole
// tag counts too, because 13 artists here are named for one ("Jay-Z / Linkin
// Park", "Ludwig van Beethoven; Maria Grinberg") and are real rows with
// tracks. Pure.
func creditNames(tags ...string) []string {
	split := func(r rune) bool { return r == ';' || r == '|' || r == '/' }
	seen := map[string]bool{}
	var out []string
	for _, tag := range tags {
		for _, part := range append(strings.FieldsFunc(tag, split), tag) {
			if name := sqliteLower(strings.TrimSpace(part)); name != "" && !seen[name] {
				seen[name] = true
				out = append(out, name)
			}
		}
	}
	return out
}

// sqliteLower lowercases as SQLite's lower() does: ASCII only. The names are
// matched against lower(i.name) in SQL, and Go's strings.ToLower folds "Ÿ" to
// "ÿ" where SQLite leaves it — so JAŸ-Z, credited on four tracks, matched
// nothing until both sides folded the same way.
func sqliteLower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if 'A' <= c && c <= 'Z' {
			b[i] = c + ('a' - 'A')
		}
	}
	return string(b)
}

// duplicateArtists is every artist row that another of the same name stands
// in for: the one with albums or tracks under it is kept, and among equals the
// lowest id. Jellyfin keeps an artist per spelling of a tag, so one name can
// be several rows.
//
// One read and a pass in Go. As SQL — every artist compared with every other
// of the same name, each comparison asking twice whether either has children —
// it was two seconds of the Artists tab on its own, and the index that would
// have sped it up slowed the health report from 2 s to 2½ minutes.
func (s *Store) duplicateArtists() ([]string, error) {
	rows, err := s.DB.Query(`SELECT a.id, a.name,
		EXISTS (SELECT 1 FROM item c WHERE c.parent_id = a.id)
		FROM item a WHERE a.type = 'MusicArtist'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var all []artistEntry
	for rows.Next() {
		var a artistEntry
		if err := rows.Scan(&a.id, &a.name, &a.filled); err != nil {
			return nil, err
		}
		all = append(all, a)
	}
	return dropDuplicateArtists(all), rows.Err()
}

type artistEntry struct {
	id, name string
	filled   bool
}

// dropDuplicateArtists keeps one row per exact name. Pure.
func dropDuplicateArtists(all []artistEntry) []string {
	keep := map[string]artistEntry{}
	for _, a := range all {
		k, ok := keep[a.name]
		if !ok || (a.filled && !k.filled) || (a.filled == k.filled && a.id < k.id) {
			keep[a.name] = a
		}
	}
	var dropped []string
	for _, a := range all {
		if keep[a.name].id != a.id {
			dropped = append(dropped, a.id)
		}
	}
	return dropped
}
