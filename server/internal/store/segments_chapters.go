package store

import (
	"regexp"
	"strings"
)

// Skip marks from chapter names.
//
// The server's own markers come from Intro Skipper's analysis, and a file it
// never analysed has none — no Skip Intro, no early offer of the next episode,
// no "watched at the credits". Many anime releases name their chapters for
// exactly these parts: "OP", "Opening", "ED", "Ending", "Credits". Those names
// are taken at their word where no marker exists. A chapter spans from its own
// start to the next chapter's.

var (
	introChapter   = regexp.MustCompile(`(?i)^\s*(op|opening|intro|opening credits|op\s*\d*)\s*$`)
	outroChapter   = regexp.MustCompile(`(?i)^\s*(ed|ending|credits|end credits|outro|ending credits|ed\s*\d*)\s*$`)
	recapChapter   = regexp.MustCompile(`(?i)^\s*(recap|previously|previously on.*|story so far)\s*$`)
	previewChapter = regexp.MustCompile(`(?i)^\s*(preview|next episode|next time|next episode preview|yokoku)\s*$`)
)

// ChapterSegments turns named chapters into Intro and Outro marks. Pure.
func ChapterSegments(itemID string, chapters []Chapter, runtimeTicks int64) []Segment {
	var out []Segment
	for i, c := range chapters {
		kind := ""
		switch {
		case introChapter.MatchString(c.Name):
			kind = "Intro"
		case outroChapter.MatchString(c.Name):
			kind = "Outro"
		case recapChapter.MatchString(c.Name):
			kind = "Recap"
		case previewChapter.MatchString(c.Name):
			kind = "Preview"
		default:
			continue
		}
		end := runtimeTicks
		if i+1 < len(chapters) {
			end = chapters[i+1].StartTicks
		}
		if !Believable(kind, c.StartTicks, end, runtimeTicks) {
			continue
		}
		out = append(out, Segment{ItemID: itemID, Type: kind, StartTicks: c.StartTicks, EndTicks: end})
	}
	return out
}

// OnlyTypes keeps the segments of the asked-for types; none asked means all.
func OnlyTypes(segments []Segment, types []string) []Segment {
	if len(types) == 0 {
		return segments
	}
	var out []Segment
	for _, s := range segments {
		for _, t := range types {
			if strings.EqualFold(s.Type, t) {
				out = append(out, s)
				break
			}
		}
	}
	return out
}

// FillMissingTypes adds chapter-derived marks of the types `have` lacks. The
// analysed marks win wherever they exist; chapters fill in the rest — most
// often a recap, which the analysis never looks for. Pure.
func FillMissingTypes(have, fromChapters []Segment) []Segment {
	present := map[string]bool{}
	for _, s := range have {
		present[strings.ToLower(s.Type)] = true
	}
	out := append([]Segment(nil), have...)
	for _, s := range fromChapters {
		if !present[strings.ToLower(s.Type)] {
			out = append(out, s)
		}
	}
	return out
}

// Believable is whether a chapter-derived mark is the size and in the place
// its kind should be. Measured on this library before these limits: of 441
// "Recap" chapters, 35 ran past five minutes — one for 78 — and a "Preview"
// ran 23; skipping either would jump most of an episode. 148 previews were
// under five seconds, a button that flashes and vanishes. Pure.
func Believable(kind string, start, end, runtime int64) bool {
	const second = 10_000_000
	length := (end - start) / second
	if length < 5 {
		return false
	}
	position := 0.0
	if runtime > 0 {
		position = float64(start) / float64(runtime)
	}
	switch kind {
	case "Recap":
		return length <= 300 && position <= 0.4
	case "Preview":
		return length <= 180 && (runtime == 0 || position >= 0.75)
	case "Intro":
		return length <= 180
	case "Outro":
		return length <= 360
	}
	return false
}
