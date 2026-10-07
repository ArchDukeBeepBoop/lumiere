package store

import (
	"strings"
)

// Query is a /Items request reduced to what the SQL needs.
//
// Built as a struct rather than passed as a dozen arguments because the handler
// parses a dozen query parameters and every one of them is optional; a struct
// keeps "absent" as the zero value and makes the WHERE builder below readable.
type Query struct {
	ParentID  string
	SeriesID  string
	SeasonID  string
	LibraryID string // TopParentId — the whole library, at any depth
	Recursive bool
	Types     []string
	Genres    []string
	Years     []int
	PersonIDs []string
	// ArtistIDs narrows to what an artist made: albums filed under them or
	// credited to them, and tracks naming them. See the clause below.
	ArtistIDs []string
	// OneArtistPerName lists each artist name once. Jellyfin keeps an artist
	// found in folders and another derived from track tags as two rows — 459
	// names here — so the Artists tab showed most names twice, one of each
	// pair usually empty. The row with albums filed under it wins.
	OneArtistPerName bool
	// IDs narrows to exactly these items, in any order. `GET /Items?ids=` is
	// how the client checks a collection still exists after deleting it, and
	// how it fetches a handful of known rows in one round trip.
	IDs        []string
	SearchTerm string
	// NameFrom is the A–Z strip: titles sorting at or after this letter.
	NameFrom   string
	Filters    []string // IsPlayed, IsUnplayed, IsFavorite, ...
	SortBy     []string
	Descending bool
	StartIndex int
	Limit      int
	// FolderIDs is filled in by the store, not the handler: the physical folders
	// backing ParentID when it names a library view.
	FolderIDs []string

	// ExcludeExtras drops anything with an ExtraType. Extras are hidden from
	// shelves by the client anyway, but returning them inflates
	// TotalRecordCount, and paging is driven by that number.
	ExcludeExtras bool
}

// itemColumns is the projection every list read shares. Kept in one place
// because the scan below is positional and a column added to one and not the
// other is a silent misalignment, not a compile error.
const itemColumns = `
    i.id, i.type, i.name, i.sort_name, i.original_title, i.overview, i.tagline,
    i.parent_id, i.library_id, i.series_id, i.series_name, i.season_id,
    i.season_name, i.index_number, i.parent_index_number, i.production_year,
    i.premiere_date, i.date_created, i.official_rating, i.community_rating,
    i.critic_rating, i.runtime_ticks, i.container, i.path, i.is_folder,
    i.extra_type, i.album, i.album_artist, i.artists,
    i.collection_type, i.size, i.total_bitrate`

// where turns a Query into a SQL fragment and its arguments.
//
// Every value is a placeholder. The only strings that ever reach the SQL text
// are column names chosen from a fixed map (see orderBy), never anything from a
// request.
func (q Query) where() (string, []any) {
	var clauses []string
	var args []any

	switch {
	case q.ParentID != "" && q.Recursive:
		// Recursive means "everything under this library at any depth", and
		// library_id is Jellyfin's TopParentId — already that answer, so no
		// recursive CTE and no tree walk per page.
		//
		// But the id the client sends is the *view's*, and children carry the
		// *physical folder's*. resolveFolders turns one into the other; see the
		// library_folder table. The parent_id term stays so that asking for a
		// plain folder recursively still works.
		if len(q.FolderIDs) > 0 {
			// A resolved library: match on library_id alone. The `OR parent_id`
			// term below is redundant here — the physical folder's own row carries
			// itself as library_id — and dropping it is what lets SQLite walk the
			// (library_id, sort_name) index in order instead of sorting all 25,237
			// rows into a temp B-tree on every one of 127 pages.
			clauses = append(clauses,
				"i.library_id IN ("+placeholders(len(q.FolderIDs))+")")
			for _, id := range q.FolderIDs {
				args = append(args, id)
			}
			break
		}
		// An unresolved id: a plain folder, or a view with no physical folders.
		clauses = append(clauses, "(i.library_id = ? OR i.parent_id = ?)")
		args = append(args, q.ParentID, q.ParentID)
	case q.ParentID != "":
		// The view's own id as well as the folders behind it: a plain folder
		// resolves to nothing and matches itself, and a library view matches the
		// physical folders its children are actually filed under.
		//
		// Or a link. A collection's or a playlist's members are not its
		// children — a film is filed under its folder and can be in any number
		// of collections besides — so they hang off the link table. A plain
		// folder has no links and the OR adds nothing; see the link table.
		ids := append([]string{q.ParentID}, q.FolderIDs...)
		clauses = append(clauses,
			"(i.parent_id IN ("+placeholders(len(ids))+")"+
				" OR i.id IN (SELECT child_id FROM link WHERE parent_id = ?))")
		for _, id := range ids {
			args = append(args, id)
		}
		args = append(args, q.ParentID)
	case len(q.IDs) > 0:
		clauses = append(clauses, "i.id IN ("+placeholders(len(q.IDs))+")")
		for _, id := range q.IDs {
			args = append(args, id)
		}
	case q.LibraryID != "":
		clauses = append(clauses, "i.library_id = ?")
		args = append(args, q.LibraryID)
	}

	if q.SeriesID != "" {
		clauses = append(clauses, "i.series_id = ?")
		args = append(args, q.SeriesID)
	}
	if q.SeasonID != "" {
		clauses = append(clauses, "i.season_id = ?")
		args = append(args, q.SeasonID)
	}
	if len(q.Types) > 0 {
		clauses = append(clauses, "i.type IN ("+placeholders(len(q.Types))+")")
		for _, t := range q.Types {
			args = append(args, t)
		}
	}
	if q.SearchTerm != "" {
		// Both titles, because a romaji or original title is often what someone
		// types for anime — the client matches on OriginalTitle for exactly this
		// reason (§5.2).
		// ESCAPE is required for escapeLike below to mean anything: without
		// it the backslashes are literal characters and typing "%" still
		// matches the whole library.
		clauses = append(clauses,
			`(i.name LIKE ? ESCAPE '\' OR i.original_title LIKE ? ESCAPE '\')`)
		like := "%" + escapeLike(q.SearchTerm) + "%"
		args = append(args, like, like)
	}
	if q.NameFrom != "" {
		clauses = append(clauses, "COALESCE(i.sort_name, i.name) >= ? COLLATE NOCASE")
		args = append(args, q.NameFrom)
	}
	if len(q.Years) > 0 {
		clauses = append(clauses, "i.production_year IN ("+placeholders(len(q.Years))+")")
		for _, y := range q.Years {
			args = append(args, y)
		}
	}
	for _, g := range q.Genres {
		// One EXISTS per genre, so multiple genres mean AND rather than OR: asking
		// for Horror and Comedy should narrow, not widen.
		clauses = append(clauses,
			`EXISTS (SELECT 1 FROM item_value v
			         WHERE v.item_id = i.id AND v.kind = 'genre'
			           AND lower(v.value) = lower(?))`)
		args = append(args, g)
	}
	if len(q.PersonIDs) > 0 {
		clauses = append(clauses,
			`EXISTS (SELECT 1 FROM person p WHERE p.item_id = i.id
			           AND p.person_id IN (`+placeholders(len(q.PersonIDs))+`))`)
		for _, p := range q.PersonIDs {
			args = append(args, p)
		}
	}
	// An artist's albums and tracks. Ignored until now, so "this artist's
	// albums" answered with the first albums of the whole library, sorted by
	// date — an artist page full of other people's music.
	//
	// Filed under the artist, credited to them as album artist, or — for a
	// track — naming them among its artists (Jellyfin keeps those pipe-
	// separated). An album counts too when a track on it names them, which
	// is how a featured artist's page finds the compilation they are on.
	if len(q.ArtistIDs) > 0 {
		ids := placeholders(len(q.ArtistIDs))
		clauses = append(clauses, `(
			i.parent_id IN (`+ids+`)
			OR i.album_artist IN (SELECT a.name FROM item a WHERE a.id IN (`+ids+`))
			OR (i.type = 'Audio' AND EXISTS (SELECT 1 FROM item a WHERE a.id IN (`+ids+`)
			    AND '|' || COALESCE(i.artists, '') || '|' LIKE '%|' || a.name || '|%'))
			OR (i.type = 'MusicAlbum' AND EXISTS (SELECT 1 FROM item t, item a
			    WHERE t.parent_id = i.id AND t.type = 'Audio' AND a.id IN (`+ids+`)
			    AND '|' || COALESCE(t.artists, '') || '|' LIKE '%|' || a.name || '|%')))`)
		for n := 0; n < 4; n++ {
			for _, a := range q.ArtistIDs {
				args = append(args, a)
			}
		}
	}
	if q.OneArtistPerName {
		clauses = append(clauses, `NOT EXISTS (
			SELECT 1 FROM item d WHERE d.type = 'MusicArtist' AND d.name = i.name AND d.id <> i.id
			AND ((EXISTS (SELECT 1 FROM item c WHERE c.parent_id = d.id)
			      AND NOT EXISTS (SELECT 1 FROM item c WHERE c.parent_id = i.id))
			  OR ((EXISTS (SELECT 1 FROM item c WHERE c.parent_id = d.id))
			      = (EXISTS (SELECT 1 FROM item c WHERE c.parent_id = i.id)) AND d.id < i.id)))`)
	}
	for _, f := range q.Filters {
		switch strings.ToLower(f) {
		case "isplayed":
			clauses = append(clauses, `EXISTS (SELECT 1 FROM user_data u
			    WHERE u.item_id = i.id AND u.played = 1)`)
		case "isunplayed":
			clauses = append(clauses, `NOT EXISTS (SELECT 1 FROM user_data u
			    WHERE u.item_id = i.id AND u.played = 1)`)
		case "isfavorite", "isfavourite":
			clauses = append(clauses, `EXISTS (SELECT 1 FROM user_data u
			    WHERE u.item_id = i.id AND u.is_favorite = 1)`)
		case "isfolder":
			clauses = append(clauses, "i.is_folder = 1")
		case "isnotfolder":
			clauses = append(clauses, "i.is_folder = 0")
		case "isresumable":
			clauses = append(clauses, `EXISTS (SELECT 1 FROM user_data u
			    WHERE u.item_id = i.id AND u.position_ticks > 0)`)
			// Anything unrecognised is ignored rather than rejected. §9.3 says the
			// set Lumiere sends is unenumerated, and a filter this server has not
			// seen must not turn a working shelf into an error.
		}
	}
	if q.ExcludeExtras {
		clauses = append(clauses, "i.extra_type IS NULL")
	}

	if len(clauses) == 0 {
		return "", nil
	}
	return " WHERE " + strings.Join(clauses, " AND "), args
}

// orderBy builds a total order.
//
// The id tiebreak is not decoration: paging asks for rows 0-199, then 200-399,
// and SQLite is free to return equal-sorting rows in any order between two
// queries. Without a unique final key a 123-page sync can show one item twice
// and miss another entirely — which looks like missing media, not like a
// sorting bug.
func (q Query) orderBy() string {
	var parts []string
	for _, s := range q.SortBy {
		if col, ok := sortColumns[strings.ToLower(strings.TrimSpace(s))]; ok {
			parts = append(parts, col)
		}
	}
	if len(parts) == 0 {
		parts = []string{sortColumns["sortname"]}
	}
	dir := " ASC"
	if q.Descending {
		dir = " DESC"
	}
	// RANDOM() takes no direction, and asking for it descending is meaningless
	// rather than an error.
	joined := strings.Join(parts, dir+", ") + dir
	return " ORDER BY " + joined + ", i.id"
}

func (q Query) limitClause() (string, []any) {
	limit := q.Limit
	if limit <= 0 {
		// No limit means no limit — the sync's own paging is the bound, and
		// inventing a default here would truncate a library silently.
		limit = -1
	}
	return " LIMIT ? OFFSET ?", []any{limit, q.StartIndex}
}

func placeholders(n int) string {
	return strings.TrimSuffix(strings.Repeat("?,", n), ",")
}

// escapeLike neutralises the wildcards inside a search term so that typing "%"
// searches for a percent sign rather than matching the whole library.
func escapeLike(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(s)
}
