package subs

import (
	"bufio"
	"io"
	"strconv"
	"strings"
	"time"
)

// Reading a subtitle's timings, and nothing else about it.
//
// The syncer does not care what the lines say — only when somebody is
// speaking. That is the whole trick borrowed from ffsubsync: a subtitle is a
// record of speech over time, and so is the audio, so the offset between
// them is the lag that makes one line up with the other.

// Cue is one subtitle line's span, in seconds from the start.
type Cue struct{ Start, End float64 }

// ParseCues reads SRT, VTT or ASS timings. Unknown text yields nothing
// rather than an error: a file the syncer cannot read is a file it declines
// to sync, which is better than a confident wrong answer.
func ParseCues(text io.Reader) []Cue {
	var cues []Cue
	scanner := bufio.NewScanner(text)
	scanner.Buffer(make([]byte, 0, 64<<10), 4<<20)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if cue, ok := parseTimingLine(line); ok {
			cues = append(cues, cue)
			continue
		}
		if cue, ok := parseDialogue(line); ok {
			cues = append(cues, cue)
		}
	}
	return cues
}

// parseTimingLine reads SRT and VTT: `00:01:02,500 --> 00:01:05,000`.
func parseTimingLine(line string) (Cue, bool) {
	arrow := strings.Index(line, "-->")
	if arrow < 0 {
		return Cue{}, false
	}
	start, ok := parseStamp(strings.TrimSpace(line[:arrow]))
	if !ok {
		return Cue{}, false
	}
	rest := strings.TrimSpace(line[arrow+3:])
	// VTT puts cue settings after the end stamp, space separated.
	if space := strings.IndexAny(rest, " \t"); space > 0 {
		rest = rest[:space]
	}
	end, ok := parseStamp(rest)
	if !ok || end <= start {
		return Cue{}, false
	}
	return Cue{Start: start, End: end}, true
}

// parseDialogue reads ASS and SSA: `Dialogue: 0,0:01:02.50,0:01:05.00,...`.
func parseDialogue(line string) (Cue, bool) {
	if !strings.HasPrefix(line, "Dialogue:") {
		return Cue{}, false
	}
	fields := strings.SplitN(strings.TrimPrefix(line, "Dialogue:"), ",", 4)
	if len(fields) < 3 {
		return Cue{}, false
	}
	start, ok := parseStamp(strings.TrimSpace(fields[1]))
	if !ok {
		return Cue{}, false
	}
	end, ok := parseStamp(strings.TrimSpace(fields[2]))
	if !ok || end <= start {
		return Cue{}, false
	}
	return Cue{Start: start, End: end}, true
}

// parseStamp reads h:mm:ss.cc, hh:mm:ss,mmm and mm:ss.mmm alike.
func parseStamp(text string) (float64, bool) {
	text = strings.TrimSpace(strings.ReplaceAll(text, ",", "."))
	if text == "" {
		return 0, false
	}
	parts := strings.Split(text, ":")
	if len(parts) < 2 || len(parts) > 3 {
		return 0, false
	}
	var seconds float64
	for i, part := range parts {
		value, err := strconv.ParseFloat(part, 64)
		if err != nil {
			return 0, false
		}
		// The last field is seconds, the one before minutes, the one before
		// that hours — read from the right so both shapes work.
		switch len(parts) - i {
		case 3:
			seconds += value * 3600
		case 2:
			seconds += value * 60
		default:
			seconds += value
		}
	}
	return seconds, true
}

// SpeechTrack turns cues into a boolean track sampled at `rate` hertz: true
// where a line is on screen. The same shape the audio is reduced to, so the
// two can be slid against each other.
func SpeechTrack(cues []Cue, rate int, duration time.Duration) []bool {
	samples := int(duration.Seconds() * float64(rate))
	if samples <= 0 {
		return nil
	}
	track := make([]bool, samples)
	for _, cue := range cues {
		from := int(cue.Start * float64(rate))
		to := int(cue.End * float64(rate))
		if to > samples {
			to = samples
		}
		for i := from; i >= 0 && i < to; i++ {
			track[i] = true
		}
	}
	return track
}
