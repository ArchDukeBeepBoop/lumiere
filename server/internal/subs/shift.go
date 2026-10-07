package subs

import (
	"fmt"
	"regexp"
	"strconv"
)

// Shifting a subtitle file's own timings.
//
// A sync measured in the player is a delay the player applies; a subtitle
// fetched by the queue is fixed where it lies, so every player and every
// device reads it in time. SubRip and WebVTT write HH:MM:SS,mmm (VTT with a
// dot); ASS writes H:MM:SS.cc. Every timestamp moves by the same amount, and
// none goes below zero.

var (
	srtTime = regexp.MustCompile(`(\d{1,2}):(\d{2}):(\d{2})([,.])(\d{3})`)
	assTime = regexp.MustCompile(`(\d):(\d{2}):(\d{2})\.(\d{2})`)
)

// Shift moves every timestamp in a subtitle by `seconds` (positive is later).
func Shift(text []byte, extension string, seconds float64) ([]byte, error) {
	offset := int64(seconds * 1000)
	switch extension {
	case "srt", "vtt":
		return srtTime.ReplaceAllFunc(text, func(m []byte) []byte {
			p := srtTime.FindSubmatch(m)
			ms := clock(p[1], p[2], p[3]) + atoi(p[5]) + offset
			ms = max(ms, 0)
			return []byte(fmt.Sprintf("%02d:%02d:%02d%s%03d",
				ms/3_600_000, ms/60_000%60, ms/1000%60, p[4], ms%1000))
		}), nil
	case "ass", "ssa":
		return assTime.ReplaceAllFunc(text, func(m []byte) []byte {
			p := assTime.FindSubmatch(m)
			ms := clock(p[1], p[2], p[3]) + atoi(p[4])*10 + offset
			ms = max(ms, 0)
			return []byte(fmt.Sprintf("%d:%02d:%02d.%02d",
				ms/3_600_000, ms/60_000%60, ms/1000%60, ms%1000/10))
		}), nil
	}
	return nil, fmt.Errorf("cannot shift a .%s subtitle", extension)
}

func clock(h, m, s []byte) int64 { return (atoi(h)*3600 + atoi(m)*60 + atoi(s)) * 1000 }

func atoi(b []byte) int64 {
	n, _ := strconv.ParseInt(string(b), 10, 64)
	return n
}

// Best picks the subtitle a person would have picked from the list: never a
// machine or AI translation, a trusted uploader over an unknown one, and the
// most downloaded among equals — the crowd's verdict on its timing.
func Best(found []Candidate) (Candidate, bool) {
	var best Candidate
	ok := false
	for _, c := range found {
		if c.Machine || c.AI || c.FileID == 0 {
			continue
		}
		if !ok || (c.FromTrust && !best.FromTrust) ||
			(c.FromTrust == best.FromTrust && c.Downloads > best.Downloads) {
			best, ok = c, true
		}
	}
	return best, ok
}
