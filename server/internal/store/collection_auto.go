package store

import (
	"strings"
)

// Collections made by the server, room by room. See api.AutoCollections.

// FilmNeedingSeries is a film with a movie-database id whose film series was
// never asked for.
type FilmNeedingSeries struct{ ID, Tmdb string }

// FilmsNeedingSeries lists up to `limit` of them. Only the Jellyfin import
// ever recorded a film's series; films named since joined none.
func (s *Store) FilmsNeedingSeries(limit int) []FilmNeedingSeries {
	rows, err := s.DB.Query(`
		SELECT i.id, v.value FROM item i
		JOIN item_value v ON v.item_id = i.id AND v.kind = 'provider:Tmdb' AND v.value <> ''
		WHERE i.type = 'Movie'
		  AND NOT EXISTS (SELECT 1 FROM item_value c WHERE c.item_id = i.id
		                  AND c.kind IN ('provider:TmdbCollection', 'tmdb_series:checked'))
		LIMIT ?`, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []FilmNeedingSeries
	for rows.Next() {
		var f FilmNeedingSeries
		rows.Scan(&f.ID, &f.Tmdb)
		out = append(out, f)
	}
	return out
}

// LibraryRooms describes each library folder: whether it is private, and
// whether automatic collections leave it out (3D and My Videos — clips, not
// films in series).
type LibraryRooms struct {
	Private  map[string]bool // folder id → private
	Excluded map[string]bool // folder id → never collected automatically
	View     map[string]string
}

var autoExcludedNames = map[string]bool{"3d": true, "my videos": true}

func (s *Store) LibraryRooms(privateViews []string) LibraryRooms {
	out := LibraryRooms{Private: map[string]bool{}, Excluded: map[string]bool{}, View: map[string]string{}}
	private := map[string]bool{}
	for _, v := range privateViews {
		private[v] = true
	}
	rows, err := s.DB.Query(`SELECT lf.folder_id, lf.view_id, COALESCE(v.name, '') FROM library_folder lf
		LEFT JOIN item v ON v.id = lf.view_id`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var folder, view, name string
		rows.Scan(&folder, &view, &name)
		out.View[folder] = view
		out.Private[folder] = private[view] || private[folder]
		out.Excluded[folder] = autoExcludedNames[strings.ToLower(strings.TrimSpace(name))]
	}
	return out
}

// ItemLibrary is the library folder an item is in.
func (s *Store) ItemLibrary(id string) string {
	var lib string
	s.DB.QueryRow(`SELECT COALESCE(library_id, '') FROM item WHERE id = ?`, id).Scan(&lib)
	return lib
}

// CreateCollectionIn makes a collection inside a library rather than under
// Collections — how a private library's collections stay in its room.
func (s *Store) CreateCollectionIn(name, library string, members []string) (string, error) {
	id, err := s.CreateContainer("BoxSet", name, members)
	if err != nil || library == "" {
		return id, err
	}
	_, err = s.DB.Exec(`UPDATE item SET parent_id = ?, library_id = ? WHERE id = ?`, library, library, id)
	s.SetItemValue(id, "room:private", "1")
	return id, err
}

// SeriesCollectionFor is the collection already made for a film series in
// a room, if any.
func (s *Store) SeriesCollectionFor(tmdb string, private bool, rooms LibraryRooms) string {
	rows, err := s.DB.Query(`SELECT b.id, COALESCE(b.library_id, '') FROM item b
		JOIN item_value v ON v.item_id = b.id AND v.kind = 'tmdb_collection' AND v.value = ?
		WHERE b.type = 'BoxSet'`, tmdb)
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

// CollectionHolding is the collection already holding most of these films,
// if any — a collection made by hand or by Jellyfin with no series id, which
// an automatic pass must adopt rather than duplicate.
func (s *Store) CollectionHolding(members []string) string {
	if len(members) == 0 {
		return ""
	}
	args := make([]any, len(members))
	for i, m := range members {
		args[i] = m
	}
	var id string
	s.DB.QueryRow(`SELECT l.parent_id FROM link l JOIN item b ON b.id = l.parent_id AND b.type = 'BoxSet'
		WHERE l.child_id IN (`+placeholders(len(members))+`)
		GROUP BY l.parent_id ORDER BY count(*) DESC LIMIT 1`, args...).Scan(&id)
	return id
}
