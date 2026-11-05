package store

import (
	"reflect"
	"testing"
)

func TestCreditNamesSplitLikeTheScannerAndKeepTheWholeTag(t *testing.T) {
	got := creditNames("Jay-Z / Linkin Park", "Jay-Z; Rihanna|JAŸ-Z")
	want := []string{"jay-z", "linkin park", "jay-z / linkin park", "rihanna", "jaŸ-z", "jay-z; rihanna|jaŸ-z"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %q\nwant %q", got, want)
	}
}

func TestSQLiteLowerFoldsASCIIOnly(t *testing.T) {
	// SQLite's lower() leaves "Ÿ" alone; matching against it means doing the same.
	if got := sqliteLower("JAŸ-Z"); got != "jaŸ-z" {
		t.Errorf("%q", got)
	}
}

func TestALibrarysArtistsAreThoseItsTracksCredit(t *testing.T) {
	s := testStore(t)
	lib, err := s.CreateLibrary("Music", "music", []string{"/m"})
	if err != nil {
		t.Fatal(err)
	}
	folders, _ := s.resolveFolders(lib)
	for _, stmt := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES
			('a1', 'MusicArtist', 'JAŸ-Z', 1), ('a2', 'MusicArtist', 'Linkin Park', 1),
			('a3', 'MusicArtist', 'Jay-Z / Linkin Park', 1), ('a4', 'MusicArtist', 'Nobody Here', 1),
			('a5', 'MusicArtist', 'Ye', 1)`,
		`INSERT INTO item (id, type, name, is_folder, library_id, artists, album_artist, path) VALUES
			('t1', 'Audio', 'One', 0, '` + folders[0] + `', 'Jay-Z / Linkin Park', 'Jay-Z / Linkin Park', '/m/1.flac'),
			('t2', 'Audio', 'Two', 0, '` + folders[0] + `', 'JAŸ-Z', NULL, '/m/2.flac'),
			('t3', 'Audio', 'Three', 0, '` + folders[0] + `', 'Kanye West', NULL, '/m/3.flac')`,
	} {
		if _, err := s.DB.Exec(stmt); err != nil {
			t.Fatal(err)
		}
	}
	items, total, err := s.Items(Query{Types: []string{"MusicArtist"}, Recursive: true,
		OneArtistPerName: true, ParentID: lib, SortBy: []string{"SortName"}})
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, it := range items {
		got[it.ID] = true
	}
	if total != 3 || !got["a1"] || !got["a2"] || !got["a3"] {
		t.Errorf("want JAŸ-Z, Linkin Park and the combined name; got %d: %v", total, got)
	}
	if got["a4"] || got["a5"] {
		t.Error("an artist no track credits — or only as part of another name — was listed")
	}
}

func TestTopArtistsKeepTheirOldMatchingRule(t *testing.T) {
	artists := map[string]artistRow{
		"rihanna": {id: "r", name: "Rihanna"}, "jaŸ-z": {id: "j", name: "JAŸ-Z"},
		"various artists": {id: "v", name: "Various Artists"},
	}
	tracks := []creditedTrack{
		{artists: "JAŸ-Z + Rihanna + Ye", plays: 1},
		{artists: "Rihanna feat. JAŸ-Z", plays: 5},
		{albumArtist: "Various Artists", artists: "JAŸ-Z", plays: 9},
	}
	if got := rankArtists(tracks, artists, 10); !reflect.DeepEqual(got, []string{"j", "r"}) {
		t.Errorf("JAŸ-Z (15 plays) before Rihanna (6), compilations left out: %v", got)
	}
}

func TestOneRowPerArtistNamePrefersTheOneWithAlbums(t *testing.T) {
	got := dropDuplicateArtists([]artistEntry{
		{id: "a", name: "Hole"}, {id: "b", name: "Hole", filled: true}, {id: "c", name: "Hole", filled: true},
		{id: "d", name: "Björk"}, {id: "e", name: "hole"},
	})
	if !reflect.DeepEqual(got, []string{"a", "c"}) {
		t.Errorf("keep b (has albums, lowest such id), d and the other spelling e; dropped %v", got)
	}
}
