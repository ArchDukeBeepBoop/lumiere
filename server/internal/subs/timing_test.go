package subs

import (
	"strings"
	"testing"
	"time"
)

func TestParseCuesReadsSRTVTTAndASS(t *testing.T) {
	text := `1
00:00:10,500 --> 00:00:12,000
Hello

WEBVTT

00:01:00.000 --> 00:01:02.500 line:90%
Later

[Events]
Dialogue: 0,0:02:00.00,0:02:03.50,Default,,0,0,0,,Much later
Dialogue: 0,bad,0:02:03.50,Default,,0,0,0,,Ignored
`
	cues := ParseCues(strings.NewReader(text))
	if len(cues) != 3 {
		t.Fatalf("read %d cues, want 3: %v", len(cues), cues)
	}
	if cues[0].Start != 10.5 || cues[0].End != 12 {
		t.Errorf("srt cue = %v, want 10.5–12", cues[0])
	}
	if cues[1].Start != 60 || cues[1].End != 62.5 {
		t.Errorf("vtt cue = %v, want 60–62.5 with its settings ignored", cues[1])
	}
	if cues[2].Start != 120 || cues[2].End != 123.5 {
		t.Errorf("ass cue = %v, want 120–123.5", cues[2])
	}
}

func TestParseCuesIgnoresNonsense(t *testing.T) {
	if cues := ParseCues(strings.NewReader("just some prose\nand more")); len(cues) != 0 {
		t.Errorf("read %d cues from prose, want none", len(cues))
	}
	// An end before its start is a broken line, not a cue.
	if cues := ParseCues(strings.NewReader("00:00:10,000 --> 00:00:05,000\nx")); len(cues) != 0 {
		t.Errorf("read a backwards cue: %v", cues)
	}
}

func TestSpeechTrackMarksTheCuedSeconds(t *testing.T) {
	track := SpeechTrack([]Cue{{Start: 1, End: 2}}, 10, 3*time.Second)
	if len(track) != 30 {
		t.Fatalf("track is %d samples, want 30", len(track))
	}
	if track[9] || !track[10] || !track[19] || track[20] {
		t.Error("the cue does not cover exactly its own second")
	}
}

func TestBestShiftFindsAKnownOffset(t *testing.T) {
	// A minute of tenth-seconds with speech in three bursts, and the same
	// pattern moved forty samples — four seconds — later.
	audio := make([]bool, 600)
	for _, burst := range [][2]int{{50, 90}, {200, 260}, {400, 430}} {
		for i := burst[0]; i < burst[1]; i++ {
			audio[i] = true
		}
	}
	subtitle := make([]bool, 600)
	for i := 40; i < 600; i++ {
		subtitle[i] = audio[i-40]
	}

	shift, confidence := bestShift(centred(audio), centred(subtitle), 100)
	if shift != -40 {
		t.Errorf("shift = %d, want -40 (the subtitle is four seconds late)", shift)
	}
	if confidence < MinConfidence {
		t.Errorf("confidence = %.2f on an exact match, want at least %.2f", confidence, MinConfidence)
	}
}

func TestBestShiftIsUnsureAboutNoise(t *testing.T) {
	// Speech everywhere against speech everywhere: every shift agrees as
	// well as every other, and the answer must say so.
	audio := make([]bool, 600)
	subtitle := make([]bool, 600)
	for i := range audio {
		audio[i] = true
		subtitle[i] = true
	}
	_, confidence := bestShift(centred(audio), centred(subtitle), 100)
	if confidence >= MinConfidence {
		t.Errorf("confidence = %.2f on featureless tracks, want below %.2f", confidence, MinConfidence)
	}
}
