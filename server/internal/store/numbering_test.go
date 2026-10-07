package store

import "testing"

func TestParseEpisodeNumbering(t *testing.T) {
	cases := []struct {
		path            string
		season, episode int
		ok              bool
	}{
		// The two spellings this library actually uses.
		{"/m/Gallery Fake - 1x10 - The Happy Prince.mkv", 1, 10, true},
		{"/m/Show.S02E07.1080p.mkv", 2, 7, true},
		{"/m/Show s01 e12 [group].mkv", 1, 12, true},
		{"/m/Show - 12x104 - Long run.mkv", 12, 104, true},

		// Not evidence, and the reason the patterns are narrow: a wrong number
		// reorders the season and points a lookup at the wrong episode.
		{"/m/Gallery Fake 2005.mkv", 0, 0, false},
		{"/m/Episode 1080p.mkv", 0, 0, false},
		{"/m/Show - 05 - Title.mkv", 0, 0, false},
		{"/m/Nothing here at all.mkv", 0, 0, false},
		// The extension is stripped first, so a container that happens to read
		// like numbering cannot supply it.
		{"/m/Show.1x02.mkv", 1, 2, true},
	}

	for _, c := range cases {
		season, episode, ok := ParseEpisodeNumbering(c.path)
		if ok != c.ok || (ok && (season != c.season || episode != c.episode)) {
			t.Errorf("ParseEpisodeNumbering(%q) = %d, %d, %v; want %d, %d, %v",
				c.path, season, episode, ok, c.season, c.episode, c.ok)
		}
	}
}

func TestNumberEpisodesLeavesStatedNumbersAlone(t *testing.T) {
	s := testStore(t)
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, path, parent_index_number, index_number)
		VALUES ('e1', 'Episode', 'One', '/m/Show - 1x05 - A.mkv', NULL, NULL),
		       ('e2', 'Episode', 'Two', '/m/Show - 1x06 - B.mkv', 3, 9),
		       ('e3', 'Episode', 'Three', '/m/Show - unnumbered.mkv', NULL, NULL)`,
	); err != nil {
		t.Fatal(err)
	}

	n, err := NumberEpisodes(s.DB)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Errorf("numbered %d, want 1", n)
	}

	var season, episode int
	s.DB.QueryRow(`SELECT parent_index_number, index_number FROM item WHERE id='e1'`).
		Scan(&season, &episode)
	if season != 1 || episode != 5 {
		t.Errorf("e1 = S%dE%d, want S1E5", season, episode)
	}
	// Jellyfin's own numbering wins over the filename, however odd it looks.
	s.DB.QueryRow(`SELECT parent_index_number, index_number FROM item WHERE id='e2'`).
		Scan(&season, &episode)
	if season != 3 || episode != 9 {
		t.Errorf("e2 = S%dE%d, want the stated S3E9", season, episode)
	}
}

func TestParseEpisodeOnly(t *testing.T) {
	cases := []struct {
		path    string
		episode int
		ok      bool
	}{
		// The two files that were filed as films called "Otome Juurin Yuugi".
		{"/H/Otome Juurin Yuugi/Otome Juurin Yuugi- Garden Lantern Story Episode 2.mp4", 2, true},
		{"/H/Hoshi no Uta/Hoshi no Uta Episode 1.mp4", 1, true},
		{"/H/Inaka/Mori ni wa Nani mo Nai - 02.mkv", 2, true},
		{"/H/Show/Show Ep. 3.mkv", 3, true},
		{"/H/Show/Show E04.mkv", 4, true},
		// A full season+episode is not this parser's business.
		{"/H/Show/Show S01E05.mkv", 0, false},
		// A year and a resolution are numbers, not episodes.
		{"/H/Show/Gallery Fake 2005.mkv", 0, false},
		{"/H/Show/Show 1080p.mkv", 0, false},
		{"/H/Show/Show.mkv", 0, false},
	}
	for _, c := range cases {
		season, episode, ok := ParseEpisodeOnly(c.path)
		if ok != c.ok || episode != c.episode {
			t.Errorf("%s: got s%d e%d ok=%v, want e%d ok=%v", c.path, season, episode, ok, c.episode, c.ok)
		}
		if ok && season != 1 {
			t.Errorf("%s: season should be 1, got %d", c.path, season)
		}
	}
}
