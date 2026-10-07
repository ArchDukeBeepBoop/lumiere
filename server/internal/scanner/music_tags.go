package scanner

import (
	"encoding/json"
	"path/filepath"
	"strconv"
	"strings"
)

// MusicTags is what a track says about itself.
type MusicTags struct {
	Title, Artist, AlbumArtist, Album, Container string
	Track, Disc, Year                            int
	Ticks, Bitrate                               int64
}

// ParseMusicTags reads ffprobe's -show_format JSON. Pure: the file name and
// folder stand in for anything the tags leave out, so a bare file still has
// a title, an album and an artist.
func ParseMusicTags(probe []byte, path string) MusicTags {
	var p struct {
		Format struct {
			FormatName string            `json:"format_name"`
			Duration   string            `json:"duration"`
			BitRate    string            `json:"bit_rate"`
			Tags       map[string]string `json:"tags"`
		} `json:"format"`
	}
	json.Unmarshal(probe, &p)
	tag := func(names ...string) string {
		for _, n := range names {
			for k, v := range p.Format.Tags {
				if strings.EqualFold(k, n) && strings.TrimSpace(v) != "" {
					return strings.TrimSpace(v)
				}
			}
		}
		return ""
	}
	t := MusicTags{
		Title:       tag("title"),
		Artist:      tag("artist"),
		AlbumArtist: tag("album_artist", "albumartist", "album artist"),
		Album:       tag("album"),
		Track:       leadingNumber(tag("track", "tracknumber")),
		Disc:        leadingNumber(tag("disc", "discnumber")),
		Year:        leadingNumber(tag("date", "year", "originaldate")),
		Container:   strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), "."),
	}
	if d, err := strconv.ParseFloat(p.Format.Duration, 64); err == nil {
		t.Ticks = int64(d * 10_000_000)
	}
	t.Bitrate, _ = strconv.ParseInt(p.Format.BitRate, 10, 64)
	if t.Year < 1000 {
		t.Year = 0
	}
	base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	if t.Title == "" {
		// "1-06 Me Against the World" and "06 - Changes": the number is the
		// track, the rest the title.
		t.Title, t.Track = splitTrackPrefix(base, t.Track)
	}
	if t.AlbumArtist == "" {
		t.AlbumArtist = firstOf(splitArtists(t.Artist))
	}
	if t.AlbumArtist == "" {
		// Music/Artist/Album/track: the folder above the album.
		if grand := filepath.Base(filepath.Dir(filepath.Dir(path))); grand != "Music" && grand != "." {
			t.AlbumArtist = grand
		}
	}
	if t.Artist == "" {
		t.Artist = t.AlbumArtist
	}
	return t
}

func splitTrackPrefix(base string, track int) (string, int) {
	digits := 0
	for digits < len(base) && (base[digits] >= '0' && base[digits] <= '9' || base[digits] == '-') {
		digits++
	}
	if digits == 0 || digits > 5 || digits == len(base) {
		return base, track
	}
	number := base[:digits]
	if i := strings.LastIndex(number, "-"); i >= 0 {
		number = number[i+1:]
	}
	rest := strings.TrimLeft(base[digits:], " .-_")
	if rest == "" {
		return base, track
	}
	if track == 0 {
		track, _ = strconv.Atoi(number)
	}
	return rest, track
}

func leadingNumber(s string) int {
	end := 0
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	n, _ := strconv.Atoi(s[:end])
	return n
}

func firstOf(list []string) string {
	if len(list) == 0 {
		return ""
	}
	return list[0]
}
