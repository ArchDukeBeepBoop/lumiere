package store

import "testing"

func TestTopArtistsArePlaysThenTracks(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, library_id, album_artist, artists, parent_id) VALUES
			('al1', 'MusicAlbum', 'Rumours', 1, 'music', 'Fleetwood Mac', NULL, 'music'),
			('t1', 'Audio', 'Dreams', 0, 'music', 'Fleetwood Mac', 'Fleetwood Mac', 'al1'),
			('t2', 'Audio', 'Go Your Own Way', 0, 'music', 'Fleetwood Mac', 'Fleetwood Mac', 'al1'),
			('t3', 'Audio', 'Lean On', 0, 'music', 'Major Lazer', 'Major Lazer; DJ Snake', 'al1'),
			('t4', 'Audio', 'Mix', 0, 'music', 'Various Artists', 'Various Artists', 'al1'),
			('t5', 'Audio', 'Mix 2', 0, 'music', 'Various Artists', 'Various Artists', 'al1'),
			('t6', 'Audio', 'Mix 3', 0, 'music', 'Various Artists', 'Various Artists', 'al1'),
			('fm', 'MusicArtist', 'Fleetwood Mac', 1, NULL, NULL, NULL, NULL),
			('fm2', 'MusicArtist', 'Fleetwood Mac', 1, NULL, NULL, NULL, NULL),
			('dj', 'MusicArtist', 'DJ Snake', 1, NULL, NULL, NULL, NULL),
			('va', 'MusicArtist', 'Various Artists', 1, NULL, NULL, NULL, NULL)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('al1', 'genre', 'Rock')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('al1', 'Primary', 0, '/x.jpg', 't')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.TopArtists("music", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0] != "fm" || got[1] != "dj" {
		t.Fatalf("before plays, by tracks: %v", got)
	}
	s.DB.Exec(`INSERT INTO user_data (item_id, played, play_count, updated_at) VALUES ('t3', 1, 5, 'now')`)
	if got, _ = s.TopArtists("music", 10); got[0] != "dj" {
		t.Fatalf("plays lead: %v", got)
	}
	covers, _ := s.GenreCovers("music")
	if covers["rock"] != "al1" {
		t.Fatalf("genre covers: %v", covers)
	}
}
