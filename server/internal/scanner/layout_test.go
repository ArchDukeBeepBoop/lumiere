package scanner

import "testing"

func TestDescribeRealShapes(t *testing.T) {
	const anime = "/Volumes/Media/Anime"
	const movies = "/Volumes/Media/Movies"

	cases := []struct {
		name string
		root string
		path string
		want Layout
	}{
		{
			"a season folder under a show",
			anime,
			anime + "/Gallery Fake/Season 1/Gallery Fake - 1x10 - The Happy Prince.mkv",
			Layout{Kind: KindEpisode, Series: "Gallery Fake", SeriesPath: anime + "/Gallery Fake", Season: 1, Episode: 10, Title: "Gallery Fake"},
		},
		{
			// The filename states both numbers, so the folder is not consulted
			// — a file saying S02E05 under `Season 1` is telling you the folder
			// is wrong.
			"the filename outranks the folder",
			anime,
			anime + "/Some Show/Season 1/Some Show S02E05.mkv",
			Layout{Kind: KindEpisode, Series: "Some Show", SeriesPath: anime + "/Some Show", Season: 2, Episode: 5, Title: "Some Show"},
		},
		{
			"Specials is season zero, as Jellyfin numbers it",
			anime,
			anime + "/Some Show/Specials/A short.mkv",
			Layout{Kind: KindEpisode, Series: "Some Show", SeriesPath: anime + "/Some Show", Season: 0, Episode: 0, Title: "Some Show"},
		},
		{
			"a folder that names no season stays numberless",
			anime,
			anime + "/Some Show/Season Unknown/A short.mkv",
			Layout{Kind: KindEpisode, Series: "Some Show", SeriesPath: anime + "/Some Show", Season: -1, Episode: 0, Title: "Some Show"},
		},
		{
			"a film is its folder",
			movies,
			movies + "/2001 A Space Odyssey (1968)/2001 A Space Odyssey (1968) 2160p BluRay x265.mkv",
			Layout{Kind: KindMovie, Title: "2001 A Space Odyssey", Year: 1968},
		},
		{
			// The folder libraries: a clip with nothing above it to read.
			"a loose file stays loose",
			"/Volumes/Media/Special/3D",
			"/Volumes/Media/Special/3D/some clip 1080p.mkv",
			Layout{Kind: KindLoose, Title: "some clip"},
		},
	}

	for _, c := range cases {
		got := Describe(c.root, c.path)
		if got != c.want {
			t.Errorf("%s:\n  Describe(%q)\n  = %+v\n  want %+v", c.name, c.path, got, c.want)
		}
	}
}

func TestCleanTitle(t *testing.T) {
	cases := []struct {
		in    string
		title string
		year  int
	}{
		{"Blade Runner 2049 (2017)", "Blade Runner 2049", 2017},
		{"The.Matrix.1999.1080p.BluRay.x264", "The Matrix 1999", 0},
		{"Some Show - 2160p REMUX", "Some Show", 0},
		{"86 Eighty Six", "86 Eighty Six", 0},
		// A year inside the title, not in brackets, is part of the title —
		// 2001 and 1917 are films, not release dates.
		{"2001 A Space Odyssey (1968)", "2001 A Space Odyssey", 1968},
	}
	for _, c := range cases {
		title, year := CleanTitle(c.in)
		if title != c.title || year != c.year {
			t.Errorf("CleanTitle(%q) = %q, %d; want %q, %d", c.in, title, year, c.title, c.year)
		}
	}
}

func TestIsMedia(t *testing.T) {
	if !IsMedia("/m/Show.mkv") || !IsMedia("/m/Show.MP4") {
		t.Error("a container this server serves should be media")
	}
	// A media tree on a Mac is full of these, and each one is four kilobytes of
	// metadata that would otherwise be catalogued as an episode.
	if IsMedia("/m/._Show.mkv") {
		t.Error("a resource fork is not media")
	}
	if IsMedia("/m/Show.nfo") || IsMedia("/m/poster.jpg") {
		t.Error("metadata is not media")
	}
}

func TestItemIDIsStableAndPathSpecific(t *testing.T) {
	a := ItemID("/m/Show/S01E01.mkv")
	if a != ItemID("/m/Show/S01E01.mkv") {
		t.Error("the same file must scan to the same id, or every scan doubles the library")
	}
	if a == ItemID("/m/Show/S01E02.mkv") {
		t.Error("two files must not share an id")
	}
	if len(a) != 32 {
		t.Errorf("id is %d characters, want 32 to match every other id here", len(a))
	}
}

func TestExtraType(t *testing.T) {
	const root = "/m/Anime"
	cases := []struct{ path, want string }{
		// The 1,052 that filled every Latest shelf on the first run.
		{root + "/Show/Season 1/Show - NCOP1.mkv", "Clip"},
		{root + "/Show/Season 1/Show - NCED2.mkv", "Clip"},
		{root + "/Show/Extras/Clean Opening.mkv", "Clip"},
		// Its own name says what it is; the Specials folder says only that it
		// is a special, which is a season, not a supplement.
		{root + "/Show/Specials/Making of.mkv", "BehindTheScenes"},
		{root + "/Film (2019)/Film - Deleted Scenes.mkv", "DeletedScene"},
		{root + "/Film (2019)/Film - Trailer.mkv", "Trailer"},

		// Content, and the reason the patterns are narrow. An episode wrongly
		// classified is an episode nobody can find.
		{root + "/Show/Season 1/Show - 1x01 - Pilot.mkv", ""},
		{root + "/Show/Season 1/Operation Downfall.mkv", ""},
		{root + "/Show/Season 1/Show - 1x02 - The Preview Man.mkv", ""},
		// Anchoring is what saves these: the word is in the title, not the role.
		{root + "/Show/Season 1/Show - 1x03 - Trailer Park.mkv", ""},
		{root + "/Show/Season 1/Show - 1x04 - The Interview.mkv", ""},
	}
	for _, c := range cases {
		if got := ExtraType(root, c.path); got != c.want {
			t.Errorf("ExtraType(%q) = %q, want %q", c.path, got, c.want)
		}
	}
}

func TestALibraryNamedSpecialsIsNotAllExtras(t *testing.T) {
	// The root itself is never read as an extras folder, or a library called
	// "Specials" would be entirely invisible.
	const root = "/m/Specials"
	if got := ExtraType(root, root+"/Show/Season 1/ep.mkv"); got != "" {
		t.Errorf("ExtraType = %q, want content", got)
	}
}

func TestAnExtrasFolderDoesNotMakeAFilmIntoAShow(t *testing.T) {
	// Four Ghost in the Shell films with an EXTRA folder beside them. `EXTRA`
	// used to read as a season, so the scanner built a series for a folder
	// whose contents were already catalogued as movies — and it then sat in
	// Recently Added with no artwork, which is how it was found.
	const root = "/m/Anime Movies"
	got := Describe(root, root+"/Ghost in the Shell Arise - Border/EXTRA/A short.mkv")
	if got.Kind == KindEpisode {
		t.Errorf("Describe = %+v; an extras folder is not a season", got)
	}

	// The films themselves are still films.
	film := Describe(root, root+"/Ghost in the Shell Arise - Border/Border 1 (2013).mkv")
	if film.Kind != KindMovie {
		t.Errorf("Describe = %+v, want a movie", film)
	}

	// And Specials under a real show is still a season, which is the case the
	// pattern exists for.
	special := Describe("/m/Anime", "/m/Anime/Some Show/Specials/A short.mkv")
	// Season 0, as Jellyfin numbers specials.
	if special.Kind != KindEpisode || special.Season != 0 {
		t.Errorf("Describe = %+v, want season zero of a show", special)
	}
}

func TestDescribeEpisodeOnlyNumbering(t *testing.T) {
	root := "/Volumes/M/Adult"
	layout := Describe(root, root+"/Otome Juurin Yuugi/Otome Juurin Yuugi- Garden Lantern Story Episode 2.mp4")
	if layout.Kind != KindEpisode {
		t.Fatalf("want an episode, got kind %d", layout.Kind)
	}
	if layout.Series != "Otome Juurin Yuugi" || layout.Season != 1 || layout.Episode != 2 {
		t.Errorf("got %q s%d e%d", layout.Series, layout.Season, layout.Episode)
	}
	if layout.SeriesPath != root+"/Otome Juurin Yuugi" {
		t.Errorf("series path %q", layout.SeriesPath)
	}

	// A film in its own folder is still a film: no episode word, no number set
	// off by a dash.
	film := Describe("/Volumes/M/Movies", "/Volumes/M/Movies/Blade Runner (1982)/Blade Runner (1982).mkv")
	if film.Kind != KindMovie {
		t.Errorf("a film became kind %d", film.Kind)
	}
}

func TestASeasonFolderMayCarryASubtitle(t *testing.T) {
	layout := Describe("/m/Anime", "/m/Anime/Aquarion/Season 2 - Evol/Extras/Aquarion - S02 NCOP 01a.mkv")
	if layout.Kind != KindEpisode || layout.Season != 2 || layout.Series != "Aquarion" {
		t.Errorf("got %+v, want season 2 of Aquarion", layout)
	}
	if kind := ExtraType("/m/Anime", "/m/Anime/Aquarion/Season 2 - Evol/Extras/Aquarion - S02 NCOP 01a.mkv"); kind == "" {
		t.Error("an NCOP in an Extras folder is still a supplement")
	}
}
