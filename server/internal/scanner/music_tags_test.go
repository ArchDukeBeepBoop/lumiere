package scanner

import "testing"

func TestMusicTagsFromProbe(t *testing.T) {
	probe := []byte(`{"format":{"duration":"245.5","bit_rate":"320000","tags":{
		"TITLE":"Changes","ARTIST":"2Pac; Talent","album_artist":"2Pac","album":"Greatest Hits",
		"track":"5/25","disc":"1/2","date":"1998-11-24"}}}`)
	got := ParseMusicTags(probe, "/M/2Pac/Greatest Hits/1-05 Changes.flac")
	if got.Title != "Changes" || got.AlbumArtist != "2Pac" || got.Track != 5 || got.Disc != 1 ||
		got.Year != 1998 || got.Ticks != 2455000000 || got.Container != "flac" {
		t.Errorf("%+v", got)
	}
	if a := splitArtists(got.Artist); len(a) != 2 || a[1] != "Talent" {
		t.Errorf("artists %v", a)
	}
}

func TestBareFileIsNamedByItsPath(t *testing.T) {
	got := ParseMusicTags(nil, "/Volumes/M/Music/Hans Zimmer/Interstellar/1-06 Cornfield Chase.mp3")
	if got.Title != "Cornfield Chase" || got.Track != 6 || got.AlbumArtist != "Hans Zimmer" {
		t.Errorf("%+v", got)
	}
	if loose := ParseMusicTags(nil, "/Volumes/M/Music/Naruto - Wind Trap Remix.mp3"); loose.Title != "Naruto - Wind Trap Remix" {
		t.Errorf("%+v", loose)
	}
}

func TestMusicGenresKeepTheSlashInAName(t *testing.T) {
	probe := []byte(`{"format": {"tags": {"GENRE": "Hip-Hop/Rap; R&B;hip-hop/rap", "title": "x"}}}`)
	got := ParseMusicTags(probe, "/Music/A/B/01 x.m4a").Genres
	if len(got) != 2 || got[0] != "Hip-Hop/Rap" || got[1] != "R&B" {
		t.Fatalf("genres %q", got)
	}
}
