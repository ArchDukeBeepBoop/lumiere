package scanner

import (
	"lumiere-server/internal/store"
	"path/filepath"
	"regexp"
	"strings"
)

// extraPatterns name the files that are supplements rather than episodes.
//
// Creditless openings and endings above all — `NCOP`, `NCED`, `Clean Opening` —
// which a release carries beside the episodes and which Jellyfin classifies as
// extras rather than cataloguing as content. The scanner has no such knowledge,
// so it filed 1,052 of them as ordinary episodes and every Latest shelf filled
// with them.
// Anchored to the end of the name, and that is the whole safety property. An
// unanchored `preview` classified "Show - 1x02 - The Preview Man" as a trailer —
// an episode made invisible by a word inside its own title. A supplement names
// itself at the end: `Show - NCOP1`, `Film - Deleted Scenes`.
var extraPatterns = []struct {
	kind    string
	pattern *regexp.Regexp
}{
	{"Clip", regexp.MustCompile(`(?i)(^|[\s._-])nc(op|ed)\s?\d*$`)},
	{"Clip", regexp.MustCompile(`(?i)(^|[\s._-])(creditless|clean)\s+(opening|ending)\s?\d*$`)},
	{"Trailer", regexp.MustCompile(`(?i)(^|[\s._-])(trailer|teaser|promo)\s?\d*$`)},
	{"BehindTheScenes", regexp.MustCompile(`(?i)(^|[\s._-])(behind the scenes|making of|featurette)\s?\d*$`)},
	{"DeletedScene", regexp.MustCompile(`(?i)(^|[\s._-])(deleted scenes?|gag reel|outtakes?|bloopers?)\s?\d*$`)},
	{"Interview", regexp.MustCompile(`(?i)(^|[\s._-])(interview|commentary)\s?\d*$`)},
}

// extraFolders are folders whose whole contents are supplements.
//
// Not Specials. That is Jellyfin's Season 0 — OVAs, picture dramas, the
// episodes that fit nowhere numbered — and the layout rules file it as a
// season. This list had it too, so every episode in a Specials folder was
// filed under a season *and* stamped as a Clip, and the shelves, which keep
// extras out, showed a Specials season with nothing in it and then hid it.
var extraFolders = regexp.MustCompile(`(?i)^(extras?|featurettes?|bonus|trailers?|other|behind the scenes|deleted scenes|interviews|scenes|shorts)$`)

// ExtraType classifies a file as a supplement, or returns empty for content.
//
// Empty means "an episode or a film", which is what the whole library filters
// on: every shelf, every count and every list carries `extra_type IS NULL`.
// Getting this wrong in the permissive direction fills the library with clutter;
// getting it wrong the other way hides an episode, so the patterns are the
// unambiguous ones only.
func ExtraType(root, path string) string {
	relative, err := filepath.Rel(root, path)
	if err != nil {
		relative = path
	}
	parts := strings.Split(filepath.ToSlash(relative), "/")

	// A folder that names itself as extras makes everything inside one.
	// Checked on the containing folders only, never on the library root: a
	// library called "Specials" would otherwise be entirely invisible.
	for _, folder := range parts[:max(0, len(parts)-1)] {
		if extraFolders.MatchString(folder) {
			return "Clip"
		}
	}

	base := parts[len(parts)-1]
	base = strings.TrimSuffix(base, filepath.Ext(base))

	// A file that states its own season and episode is content, whatever words
	// follow. "Show - 1x04 - The Interview" is an episode called The Interview;
	// anchoring alone read it as an interview featurette, which would have
	// hidden it from the library entirely. A supplement is not numbered — that
	// is the whole of why it is filed separately.
	if _, _, numbered := store.ParseEpisodeNumbering(path); numbered {
		return ""
	}
	for _, rule := range extraPatterns {
		if rule.pattern.MatchString(base) {
			return rule.kind
		}
	}
	return ""
}
