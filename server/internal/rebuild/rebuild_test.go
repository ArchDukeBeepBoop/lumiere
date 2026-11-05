package rebuild

import (
	"database/sql"
	"path/filepath"
	"reflect"
	"testing"

	_ "modernc.org/sqlite"

	"lumiere-server/internal/store"
)

func TestRootsSeparateLibrariesSharingAParent(t *testing.T) {
	got := Roots(map[string]string{
		"/Volumes/D/Anime/Show A/Season 1": "anime",
		"/Volumes/D/Anime/Show B":          "anime",
		"/Volumes/D/Special/3D":            "3d",
		"/Volumes/D/Special/Live/clips":    "videos",
		"/Volumes/D/Special/Live":          "videos",
		"/Volumes/D/Special/Live-x":        "other",
	})
	want := map[string][]string{
		"anime":  {"/Volumes/D/Anime"},
		"3d":     {"/Volumes/D/Special/3D"},
		"videos": {"/Volumes/D/Special/Live"},
		"other":  {"/Volumes/D/Special/Live-x"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("roots:\n got %v\nwant %v", got, want)
	}
}

// A cache shaped like the app's, with the parts the rebuild reads.
func fakeCache(t *testing.T) string {
	path := filepath.Join(t.TempDir(), "cache.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, stmt := range []string{
		`CREATE TABLE library (id TEXT PRIMARY KEY, serverId TEXT, name TEXT, collectionType TEXT)`,
		`CREATE TABLE item (id TEXT PRIMARY KEY, type TEXT, name TEXT, sortName TEXT, originalTitle TEXT,
			overview TEXT, parentId TEXT, seriesId TEXT, seriesName TEXT, seasonId TEXT, indexNumber INTEGER,
			parentIndexNumber INTEGER, productionYear INTEGER, premiereDate TEXT, dateCreated TEXT,
			officialRating TEXT, communityRating REAL, runTimeTicks INTEGER, genres TEXT, studios TEXT,
			path TEXT, extraType TEXT, libraryId TEXT, album TEXT, albumArtist TEXT, artists TEXT, isFolder BOOLEAN)`,
		`CREATE TABLE userData (itemId TEXT PRIMARY KEY, played BOOLEAN, playbackPositionTicks INTEGER,
			playCount INTEGER, isFavorite BOOLEAN, lastPlayedDate TEXT, updatedAt TEXT)`,
		`INSERT INTO library VALUES ('tv','s','TV','tvshows'), ('films','s','Films','movies'),
			('locallib:opened','s','Opened Files',NULL), ('col','s','Collections','boxsets')`,
		// Jellyfin's folder row for the library root: not synced as a parent,
		// and must not come back as a folder inside its own library.
		`INSERT INTO item (id,type,name,sortName,path,libraryId,isFolder) VALUES
			('root','Folder','TV','tv','/Volumes/D/TV','tv',1),
			('show','Series','A Show','show','/Volumes/D/TV/A Show','tv',1),
			('s1','Season','Season 1','s1','/Volumes/D/TV/A Show/Season 1','tv',1),
			('e1','Episode','Pilot','pilot','/Volumes/D/TV/A Show/Season 1/e1.mkv','tv',0),
			('film','Movie','A Film','film','/Volumes/D/Films/A Film (2001)/a.mp4','films',0),
			('opened','Video','x','x','/Volumes/D/TV/A Show/Season 1/e1.mkv','locallib:opened',0),
			('box','BoxSet','Set','set',NULL,'films',1)`,
		`UPDATE item SET parentId = 'show', seriesId = 'show' WHERE id = 's1'`,
		`UPDATE item SET parentId = 's1', seriesId = 'show', seasonId = 's1', genres = 'Drama' || char(10) || 'Crime' WHERE id = 'e1'`,
		`UPDATE item SET parentId = 'jellyfin-folder' WHERE id IN ('show', 'film')`,
		`INSERT INTO userData VALUES ('e1',1,0,2,0,'2026-10-01 10:00:00.000','2026-10-01 10:00:00.000'),
			('film',0,6000000000,0,1,NULL,'2026-10-02 10:00:00.000'),
			('opened',1,0,1,0,NULL,NULL), ('nothing',0,0,0,0,NULL,NULL)`,
	} {
		if _, err := db.Exec(stmt); err != nil {
			t.Fatalf("%s: %v", stmt, err)
		}
	}
	return path
}

func TestRebuildKeepsIdsAndWatchState(t *testing.T) {
	db, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	rep, err := FromClientCache(fakeCache(t), db, Options{PrivateLibraries: []string{"films"}})
	if err != nil {
		t.Fatal(err)
	}
	want := Report{Libraries: 2, Folders: 2, Items: 4, Skipped: 1, Watched: 1, InProgress: 1, Favorites: 1}
	if rep != want {
		t.Fatalf("report %+v, want %+v", rep, want)
	}

	var parent, library, genres string
	db.DB.QueryRow(`SELECT parent_id, library_id FROM item WHERE id = 'show'`).Scan(&parent, &library)
	if parent != library || library == "" {
		t.Errorf("a show whose parent was not synced hangs from its library folder: parent %q, library %q", parent, library)
	}
	db.DB.QueryRow(`SELECT parent_id FROM item WHERE id = 'e1'`).Scan(&parent)
	if parent != "s1" {
		t.Errorf("an episode keeps its season: %q", parent)
	}
	db.DB.QueryRow(`SELECT group_concat(value, ',') FROM (SELECT value FROM item_value WHERE item_id = 'e1' AND kind = 'genre' ORDER BY value)`).Scan(&genres)
	if genres != "Crime,Drama" {
		t.Errorf("genres %q", genres)
	}

	libs, err := db.ListLibraries()
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) != 2 || libs[1].ID != "tv" || libs[1].Folders[0].Path != "/Volumes/D/TV" || libs[1].Items != 1 {
		t.Errorf("libraries keep their ids and find their folder: %+v", libs)
	}

	var played, count int
	var ticks int64
	db.DB.QueryRow(`SELECT played, play_count FROM user_data WHERE item_id = 'e1'`).Scan(&played, &count)
	db.DB.QueryRow(`SELECT position_ticks FROM user_data WHERE item_id = 'film'`).Scan(&ticks)
	if played != 1 || count != 2 || ticks != 6000000000 {
		t.Errorf("watch state: played %d count %d ticks %d", played, count, ticks)
	}
	if v, _ := db.Meta("private_libraries"); v != "films" {
		t.Errorf("private libraries %q", v)
	}
}
