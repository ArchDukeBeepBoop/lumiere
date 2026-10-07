package scanner

import (
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"lumiere-server/internal/store"
)

// Layout is what a path says an item is.
//
// Pure, and it has to be: this is the judgement the whole scan rests on, every
// rule in it is a guess about somebody's folder naming, and the only way to know
// whether a rule is right is to run it against real names. Those are facts about
// strings, testable without a disk.
type Layout struct {
	// Kind is what to file this as.
	Kind Kind
	// SeriesPath is the show's own folder, which is how an existing series is
	// found. Matching by *name* split shows in two: the folder is `Dr Stone`
	// and the scraped title is `Dr. STONE`, so the scanner made a second,
	// posterless series beside the real one and filed the episodes there. A
	// path is the same string on both sides or it is a different show.
	SeriesPath string
	// Series and Season are set for an episode. Season is -1 where the folder
	// names no number — "Specials", "Season Unknown" — which stays distinct
	// from season 0.
	Series  string
	Season  int
	Episode int
	// Title is the display name: the show's name for an episode, the film's
	// name for a film, always with the release year and the scene tags removed.
	Title string
	Year  int
}

type Kind int

const (
	// KindMovie is a file whose folder is the title. `Movies/Blade Runner
	// (1982)/Blade Runner (1982).mkv`.
	KindMovie Kind = iota
	// KindEpisode is a file under a season folder, or a file whose name states
	// a season and episode number.
	KindEpisode
	// KindLoose is a file this cannot place — a clip at the root of a folder
	// library, which is most of what "3D" and "My Videos" hold. Filed as a
	// video with no series and no year, which is what those libraries want.
	KindLoose
)

// seasonFolder matches the folder that names a season.
//
// `Season 2`, `season 02`, `S2`, and the two ways a scanner writes "we could not
// tell": Specials and Season Unknown, which are common enough in this library to
// be worth naming rather than falling through to "loose".
var (
	// With or without a subtitle: `Season 2`, `Season 2 - Evol`, `Season 2:
	// Brotherhood`. The number is what names the season; what follows a
	// dash or colon is what the season is called.
	seasonFolder = regexp.MustCompile(`(?i)^(?:season|series|s)[\s._-]*(\d{1,3})(?:\s*[-–:]\s*.+)?$`)
	// Specials is a season; Extras is not.
	//
	// `extras?` was in this list, and it manufactured a show out of a film: an
	// `EXTRA` folder beside four Ghost in the Shell films read as a season, so
	// the scanner built a series for a folder whose contents were already
	// catalogued as movies. A named supplements folder says what its contents
	// *are*, not that its parent is a television programme — and ExtraType
	// already files them correctly without any of this.
	specialFolder = regexp.MustCompile(`(?i)^specials?$`)
	unknownFolder = regexp.MustCompile(`(?i)^season unknown$`)
	yearInName    = regexp.MustCompile(`\((19|20)\d{2}\)`)
	// The tags that follow a title in a scene release. Cut at the first one:
	// everything after is technical, and none of it belongs in a name.
	sceneTag = regexp.MustCompile(`(?i)\b(1080p|2160p|720p|480p|4k|uhd|bluray|blu-ray|bdrip|brrip|webrip|web-dl|webdl|hdtv|dvdrip|remux|x264|x265|h264|h265|hevc|avc|aac|ac3|dts|ddp?5\.1|flac|10bit|8bit|hdr10?|dv|sdr|repack|proper|extended|uncut)\b`)
)

// Describe reads a file's place in the tree.
//
// `root` is the library folder the file was found under, so the components
// between it and the file are the only ones that carry meaning — an absolute
// path would otherwise put "Volumes" and the drive name into every decision.
func Describe(root, path string) Layout {
	relative, err := filepath.Rel(root, path)
	if err != nil {
		relative = filepath.Base(path)
	}
	parts := strings.Split(filepath.ToSlash(relative), "/")
	base := strings.TrimSuffix(parts[len(parts)-1], filepath.Ext(path))

	// The filename's own numbering wins wherever it exists. It is the only
	// signal that states both numbers at once, and a file that says `S02E05`
	// under a folder called `Season 1` is telling you the folder is wrong.
	if season, episode, ok := store.ParseEpisodeNumbering(path); ok && len(parts) > 1 {
		series, year := CleanTitle(parts[0])
		return Layout{
			Kind: KindEpisode, Series: series, SeriesPath: filepath.Join(root, parts[0]),
			Season: season, Episode: episode, Title: series, Year: year,
		}
	}

	// A season folder above the file — not only immediately above. The
	// creditless openings in `Show/Season 3/Extras/NCOP1.mkv` belong to
	// season 3, and reading only the folder next to the file saw "Extras",
	// found no season, and filed a hundred and eighty-nine of them as loose
	// videos of no show. ExtraType still marks them as supplements from the
	// same path; this only decides whose supplements they are.
	if len(parts) >= 3 {
		for depth := len(parts) - 2; depth >= 1; depth-- {
			if season, ok := seasonNumber(parts[depth]); ok {
				series, year := CleanTitle(parts[0])
				return Layout{
					Kind: KindEpisode, Series: series, SeriesPath: filepath.Join(root, parts[0]),
					Season: season, Episode: episodeFromName(base),
					Title: series, Year: year,
				}
			}
		}
	}

	// A file that names its episode but not its season, inside a show's folder:
	// `Hoshi no Uta/Hoshi no Uta Episode 1.mp4`. The commonest shape in a
	// library of short series, and it used to fall through to the film rule
	// below — so two episodes became two films, both called by the folder's
	// name, and the show never existed. Depth two only: the folder is the
	// evidence that "Episode 1" is a title's episode and not a stray clip.
	if len(parts) == 2 {
		if season, episode, ok := store.ParseEpisodeOnly(path); ok {
			series, year := CleanTitle(parts[0])
			return Layout{
				Kind: KindEpisode, Series: series, SeriesPath: filepath.Join(root, parts[0]),
				Season: season, Episode: episode, Title: series, Year: year,
			}
		}
	}

	// A folder whose name is the title, holding the file. The film case, and
	// the shape almost every movie library uses.
	if len(parts) == 2 {
		title, year := CleanTitle(parts[0])
		return Layout{Kind: KindMovie, Title: title, Year: year}
	}

	// A file sitting loose in the library, or nested past anything meaningful.
	title, year := CleanTitle(base)
	return Layout{Kind: KindLoose, Title: title, Year: year}
}

func seasonNumber(folder string) (int, bool) {
	if match := seasonFolder.FindStringSubmatch(folder); match != nil {
		if n, err := strconv.Atoi(match[1]); err == nil {
			return n, true
		}
	}
	if specialFolder.MatchString(folder) {
		// Season 0, as Jellyfin numbers specials — and as the client expects,
		// which draws index 0 under its own rule in the season menu.
		return 0, true
	}
	if unknownFolder.MatchString(folder) {
		// Named, not numbered: "the folder did not say". -1 stays distinct
		// from 0, which is a real season.
		return -1, true
	}
	return 0, false
}

// episodeFromName pulls a bare episode number out of a filename.
//
// Only inside a season folder, which is what makes a bare number safe to read:
// the season is already known from the path, so the one remaining number is the
// episode. Zero where there is nothing to read — an unnumbered extra.
func episodeFromName(base string) int {
	digits := regexp.MustCompile(`\d{1,4}`).FindAllString(sceneTag.ReplaceAllString(base, ""), -1)
	for _, run := range digits {
		if n, err := strconv.Atoi(run); err == nil && n > 0 && n < 2000 {
			return n
		}
	}
	return 0
}

// CleanTitle turns a folder or file name into something worth displaying.
//
// Drops the year in brackets and everything from the first scene tag onwards,
// then tidies the separators releases use instead of spaces. What is left is
// what a person would call the thing.
func CleanTitle(name string) (string, int) {
	year := 0
	if match := yearInName.FindString(name); match != "" {
		if n, err := strconv.Atoi(strings.Trim(match, "()")); err == nil {
			year = n
		}
		name = strings.Replace(name, match, "", 1)
	}
	if location := sceneTag.FindStringIndex(name); location != nil {
		name = name[:location[0]]
	}
	name = strings.NewReplacer(".", " ", "_", " ").Replace(name)
	name = strings.Trim(name, " -[](){}")
	return strings.Join(strings.Fields(name), " "), year
}
