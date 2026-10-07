package store

import (
	"strings"
	"testing"
)

// Paging is the reason this test exists. A sync asks for rows 0-199, then
// 200-399, and SQLite may return equal-sorting rows in any order between two
// queries — so without a unique final key an item can appear on two pages and
// another on none. That reads as missing media, not as a sorting bug.
func TestOrderByAlwaysEndsWithAUniqueKey(t *testing.T) {
	for _, q := range []Query{
		{},
		{SortBy: []string{"SortName"}},
		{SortBy: []string{"DateCreated"}, Descending: true},
		{SortBy: []string{"PremiereDate", "SortName"}},
		{SortBy: []string{"NoSuchColumn"}},
	} {
		got := q.orderBy()
		if !strings.HasSuffix(got, ", i.id") {
			t.Errorf("%v: no unique tiebreak: %s", q.SortBy, got)
		}
	}
}

// A SortBy value that is not in the allowlist must be dropped, not interpolated.
// This is the only place a request string could otherwise reach the SQL text.
func TestSortByIsAnAllowlist(t *testing.T) {
	q := Query{SortBy: []string{"SortName; DROP TABLE item--"}}
	got := q.orderBy()
	if strings.Contains(got, "DROP") {
		t.Fatalf("request string reached the SQL: %s", got)
	}
	if !strings.Contains(got, "sort_name") {
		t.Fatalf("did not fall back to the default order: %s", got)
	}
}

func TestWhereUsesPlaceholdersForEveryValue(t *testing.T) {
	q := Query{
		ParentID: "abc", Types: []string{"Series", "Movie"},
		Genres: []string{"Action"}, Years: []int{1999},
		SearchTerm: "anything", Filters: []string{"IsPlayed"},
		PersonIDs: []string{"def"},
	}
	sql, args := q.where()
	for _, v := range []string{"abc", "Series", "Movie", "Action", "1999", "anything", "def"} {
		if strings.Contains(sql, v) {
			t.Errorf("value %q was interpolated into the SQL", v)
		}
	}
	// Nine: the parent id is bound twice, once for children and once for
	// links — see the link table.
	if len(args) != 9 {
		t.Errorf("expected 9 bound arguments, got %d", len(args))
	}
}

// A search for "100%" must find items containing a percent sign, not match the
// whole library.
func TestEscapeLike(t *testing.T) {
	for in, want := range map[string]string{
		"100%":   `100\%`,
		"a_b":    `a\_b`,
		`back\s`: `back\\s`,
		"plain":  "plain",
	} {
		if got := escapeLike(in); got != want {
			t.Errorf("escapeLike(%q) = %q, want %q", in, got, want)
		}
	}
}

// Multiple genres narrow rather than widen: Horror and Comedy means both.
func TestGenresAreAnded(t *testing.T) {
	sql, _ := Query{Genres: []string{"Horror", "Comedy"}}.where()
	if strings.Count(sql, "EXISTS") != 2 || strings.Contains(sql, " OR ") {
		t.Fatalf("genres are not ANDed: %s", sql)
	}
}

// A library view's direct children hang off its physical folders, so a flat
// listing of the view has to resolve them too. Without it a music library's
// Folders tab asked for the view's children and got nothing.
func TestFlatListingResolvesALibraryView(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, parent_id, library_id)
		VALUES ('folder', 'Folder', 'Music', NULL, 'folder'),
		       ('a1', 'MusicAlbum', 'An Album', 'folder', 'folder'),
		       ('a2', 'MusicAlbum', 'Another', 'folder', 'folder');
		INSERT INTO library_folder (view_id, folder_id) VALUES ('view', 'folder')`,
	); err != nil {
		t.Fatal(err)
	}

	items, total, err := s.Items(Query{ParentID: "view"})
	if err != nil {
		t.Fatal(err)
	}
	if total != 2 || len(items) != 2 {
		t.Fatalf("got %d items (total %d), want 2", len(items), total)
	}

	// A plain folder still matches itself, which is the case that already worked.
	if _, total, err = s.Items(Query{ParentID: "folder"}); err != nil || total != 2 {
		t.Errorf("direct folder listing: total %d, err %v; want 2", total, err)
	}
}

func TestMusicGenresAreDistinctAndScoped(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, library_id)
		VALUES ('folder', 'Folder', 'Music', 'folder'),
		       ('a1', 'Audio', 'One', 'folder'),
		       ('a2', 'Audio', 'Two', 'folder'),
		       ('v1', 'Movie', 'A Film', 'other');
		INSERT INTO library_folder (view_id, folder_id) VALUES ('view', 'folder');
		INSERT INTO item_value (item_id, kind, value) VALUES
		       ('a1', 'genre', 'Rock'), ('a2', 'genre', 'Rock'),
		       ('a2', 'genre', 'Ambient'), ('a1', 'tag', 'NotAGenre'),
		       ('v1', 'genre', 'Horror')`,
	); err != nil {
		t.Fatal(err)
	}

	got, err := s.MusicGenres("view")
	if err != nil {
		t.Fatal(err)
	}
	// Sorted, de-duplicated, music only — a film's genre is not a music genre,
	// and a tag is not a genre at all.
	want := []string{"Ambient", "Rock"}
	if len(got) != len(want) {
		t.Fatalf("genres = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("genres = %v, want %v", got, want)
			break
		}
	}
}

func TestAnArtistsAlbumsAndOneRowPerName(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('lp1', 'MusicArtist', 'Linkin Park', 1), ('lp2', 'MusicArtist', 'Linkin Park', 1), ('fm', 'MusicArtist', 'Fleetwood Mac', 1)`,
		`INSERT INTO item (id, type, name, is_folder, parent_id, album_artist) VALUES ('ht', 'MusicAlbum', 'Hybrid Theory', 1, 'lp2', 'Linkin Park'), ('rm', 'MusicAlbum', 'Rumours', 1, 'fm', 'Fleetwood Mac')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	albums, _, err := s.Items(Query{Types: []string{"MusicAlbum"}, Recursive: true, ArtistIDs: []string{"lp1"}})
	if err != nil || len(albums) != 1 || albums[0].ID != "ht" {
		t.Fatalf("the tag-derived Linkin Park should find Hybrid Theory, got %v (%v)", albums, err)
	}
	artists, _, _ := s.Items(Query{Types: []string{"MusicArtist"}, Recursive: true, OneArtistPerName: true})
	if len(artists) != 2 {
		t.Fatalf("got %d artists, want one Linkin Park and one Fleetwood Mac", len(artists))
	}
	for _, a := range artists {
		if a.Name == "Linkin Park" && a.ID != "lp2" {
			t.Errorf("kept the empty Linkin Park")
		}
	}
}

func TestATrackWithoutACoverBorrowsItsAlbums(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('al', 'MusicAlbum', 'Album', 1)`)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, parent_id) VALUES ('tr', 'Audio', 'Track', 0, 'al')`)
	s.DB.Exec(`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('al', 'Primary', 0, '/c.jpg', 'albumtag')`)
	if ref, err := s.MusicCoverFor("tr"); err != nil || ref.Tag != "albumtag" {
		t.Fatalf("got %+v (%v)", ref, err)
	}
	items, _, _ := s.Items(Query{IDs: []string{"tr"}, Recursive: true})
	if len(items) != 1 || items[0].Images["Primary"] != "albumtag" {
		t.Fatalf("the track should say it has the album's cover: %+v", items)
	}
}

func TestPeopleAreFoundByNameMostCreditedFirst(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO person (item_id, person_id, name, role, type) VALUES
		('a', 'hz', 'Hans Zimmer', '', 'Composer'), ('b', 'hz', 'Hans Zimmer', '', 'Composer'),
		('c', 'hb', 'Hans Brahm', '', 'Writer'), ('d', 'g', 'Hans Guest', '', 'GuestStar')`)
	got, err := s.SearchPeople("hans", 5)
	if err != nil || len(got) != 2 || got[0].Name != "Hans Zimmer" || got[0].Credits != 2 {
		t.Fatalf("got %+v (%v)", got, err)
	}
}

func TestTheOverviewCountsWhatIsThere(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, size) VALUES ('m', 'Movie', 'M', 0, 1000), ('e', 'Episode', 'E', 0, 50)`)
	s.DB.Exec(`INSERT INTO user_data (item_id, played, play_count, position_ticks, is_favorite, updated_at) VALUES ('m', 1, 1, 0, 0, 'x')`)
	o, err := s.LibraryOverview()
	if err != nil || o.Films != 1 || o.Episodes != 1 || o.Bytes != 1050 || o.WatchedFilms != 1 || o.Largest[0].Name != "M" {
		t.Fatalf("got %+v (%v)", o, err)
	}
}

func TestTrackColumnsSortRatherThanFallingBackToName(t *testing.T) {
	for _, field := range []string{"AlbumArtist", "Album", "ParentIndexNumber", "Runtime", "PlayCount", "DateCreated"} {
		got := Query{SortBy: []string{field}}.orderBy()
		if got == (Query{}).orderBy() {
			t.Errorf("%s sorts by name", field)
		}
	}
}

func TestNameFromJumpsToALetter(t *testing.T) {
	where, args := Query{NameFrom: "M"}.where()
	if !strings.Contains(where, ">= ?") || args[len(args)-1] != "M" {
		t.Errorf("%s %v", where, args)
	}
}
