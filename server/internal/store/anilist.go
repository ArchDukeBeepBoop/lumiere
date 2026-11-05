package store

import (
	"encoding/json"
	"strconv"
	"strings"

	"lumiere-server/internal/anilist"
)

// AniList's side of the library: which titles are which entry, and a cache of
// the entries the franchise walk has read. Entries live in meta under
// "anilist:<id>", like the TMDB series cache, so a rebuilt franchise list costs
// no requests for what was already asked. See api/collection_anilist.go.

// MetaAniListLibraries is the libraries whose titles are looked up on AniList,
// as view ids. Unset means every library whose name says Anime and that is not
// private — anything else is a choice made in Settings.
const MetaAniListLibraries = "anilist_libraries"

// AniListLibraries returns the folder ids to look up, and the views they came
// from.
func (s *Store) AniListLibraries(privateViews []string) (folders []string, views []string) {
	private := map[string]bool{}
	for _, v := range privateViews {
		private[v] = true
	}
	// Unset is the default; "none" is a choice of no libraries.
	chosen, _ := s.Meta(MetaAniListLibraries)
	picked := map[string]bool{}
	for _, v := range strings.Split(chosen, ",") {
		if v != "" {
			picked[v] = true
		}
	}
	rows, err := s.DB.Query(`SELECT v.id, v.name, lf.folder_id FROM item v
		JOIN library_folder lf ON lf.view_id = v.id
		WHERE v.type = 'CollectionFolder' AND COALESCE(v.collection_type, '') IN ('tvshows', 'movies', '')`)
	if err != nil {
		return nil, nil
	}
	defer rows.Close()
	seen := map[string]bool{}
	for rows.Next() {
		var view, name, folder string
		rows.Scan(&view, &name, &folder)
		use := picked[view] && chosen != "none"
		if chosen == "" {
			use = strings.Contains(strings.ToLower(name), "anime") && !private[view]
		}
		if !use {
			continue
		}
		folders = append(folders, folder)
		if !seen[view] {
			seen[view] = true
			views = append(views, view)
		}
	}
	return folders, views
}

// AniListCandidate is a film or show to find on AniList.
type AniListCandidate struct {
	ID, Name, Original string
	Year               int
	Film               bool
}

// AniListUnchecked lists titles in those folders never looked up.
func (s *Store) AniListUnchecked(folders []string, limit int) []AniListCandidate {
	if len(folders) == 0 {
		return nil
	}
	in := "?" + strings.Repeat(",?", len(folders)-1)
	args := []any{}
	for _, f := range folders {
		args = append(args, f)
	}
	args = append(args, limit)
	rows, err := s.DB.Query(`SELECT id, type, name, COALESCE(original_title, ''), COALESCE(production_year, 0)
		FROM item i WHERE type IN ('Series', 'Movie') AND library_id IN (`+in+`)
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id AND v.kind = 'anilist:checked')
		LIMIT ?`, args...)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []AniListCandidate
	for rows.Next() {
		var c AniListCandidate
		var typ string
		rows.Scan(&c.ID, &typ, &c.Name, &c.Original, &c.Year)
		c.Film = typ == "Movie"
		out = append(out, c)
	}
	return out
}

// SetAniListMatch records what a title is (0: asked, nothing matched), and
// its romaji, which the apps can show in place of or under the title — see
// the app's per-library title order.
func (s *Store) SetAniListMatch(itemID string, anilistID int, romaji string) {
	if anilistID > 0 {
		s.SetItemValue(itemID, "provider:AniList", strconv.Itoa(anilistID))
	}
	if romaji != "" {
		s.SetItemValue(itemID, "title:romaji", romaji)
		// item_value has no change trigger; the apps learn of it this way.
		s.DB.Exec(`INSERT INTO change_log (item_id) VALUES (?)`, itemID)
	}
	s.SetItemValue(itemID, "anilist:checked", "1")
}

// AniListMatched maps each matched AniList id to the local titles that are it.
func (s *Store) AniListMatched() map[int][]string {
	rows, err := s.DB.Query(`SELECT item_id, value FROM item_value WHERE kind = 'provider:AniList'`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := map[int][]string{}
	for rows.Next() {
		var item, value string
		rows.Scan(&item, &value)
		if id, err := strconv.Atoi(value); err == nil {
			out[id] = append(out[id], item)
		}
	}
	return out
}

// AniListNode reads a cached entry.
func (s *Store) AniListNode(id int) (anilist.Node, bool) {
	raw, _ := s.Meta("anilist:" + strconv.Itoa(id))
	if raw == "" {
		return anilist.Node{}, false
	}
	var n anilist.Node
	return n, json.Unmarshal([]byte(raw), &n) == nil
}

// SaveAniListNode caches an entry.
func (s *Store) SaveAniListNode(n anilist.Node) {
	data, _ := json.Marshal(n)
	s.SetMeta("anilist:"+strconv.Itoa(n.ID), string(data))
}

// CollectionWithValue is the collection carrying kind=value, or "".
func (s *Store) CollectionWithValue(kind, value string) string {
	var id string
	s.DB.QueryRow(`SELECT b.id FROM item b JOIN item_value v ON v.item_id = b.id
		WHERE b.type = 'BoxSet' AND v.kind = ? AND v.value = ? LIMIT 1`, kind, value).Scan(&id)
	return id
}

// CoveredByCollection says whether a collection already stands for this
// group: one with the same name (give or take "Collection"), or one holding
// every member.
func (s *Store) CoveredByCollection(name string, members []string) bool {
	folded := anilist.Normalize(strings.TrimSuffix(strings.TrimSpace(name), " Collection"))
	rows, err := s.DB.Query(`SELECT id, name FROM item WHERE type = 'BoxSet'`)
	if err != nil {
		return false
	}
	var ids []string
	for rows.Next() {
		var id, n string
		rows.Scan(&id, &n)
		if anilist.Normalize(strings.TrimSuffix(n, " Collection")) == folded {
			rows.Close()
			return true
		}
		ids = append(ids, id)
	}
	rows.Close()
	for _, id := range ids {
		var held int
		in := "?" + strings.Repeat(",?", len(members)-1)
		args := []any{id}
		for _, m := range members {
			args = append(args, m)
		}
		s.DB.QueryRow(`SELECT count(*) FROM link WHERE parent_id = ? AND child_id IN (`+in+`)`, args...).Scan(&held)
		if held == len(members) {
			return true
		}
	}
	return false
}

// SetLinkOrder puts a collection's members in this order — a franchise as it
// came out, a smart collection as its rules sort it. The app reads a
// collection in its stored order unless told otherwise.
func (s *Store) SetLinkOrder(id string, members []string) {
	for i, m := range members {
		s.DB.Exec(`UPDATE link SET position = ? WHERE parent_id = ? AND child_id = ?`, i, id, m)
	}
}

// BareSeason is a season with no picture of its own.
type BareSeason struct {
	ID, SeriesID string
	Number       int
}

// BareSeasons lists seasons with no Primary, not yet tried on AniList, of
// the given shows.
func (s *Store) BareSeasons(seriesIDs []string) []BareSeason {
	if len(seriesIDs) == 0 {
		return nil
	}
	in := "?" + strings.Repeat(",?", len(seriesIDs)-1)
	args := make([]any, len(seriesIDs))
	for i, id := range seriesIDs {
		args[i] = id
	}
	rows, err := s.DB.Query(`SELECT s.id, s.parent_id, COALESCE(s.index_number, -1) FROM item s
		WHERE s.type = 'Season' AND s.parent_id IN (`+in+`)
		  AND NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = s.id AND g.kind = 'Primary')
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = s.id AND v.kind = 'season:anilist')`, args...)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []BareSeason
	for rows.Next() {
		var b BareSeason
		rows.Scan(&b.ID, &b.SeriesID, &b.Number)
		out = append(out, b)
	}
	return out
}
