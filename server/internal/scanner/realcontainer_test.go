package scanner

import "testing"

func TestContainersAreWhatTheFileIsNotWhatItIsCalled(t *testing.T) {
	for format, want := range map[string]string{
		"mov,mp4,m4a,3gp,3g2,mj2": "mp4",
		"matroska,webm":           "mkv",
		"mpegts":                  "mpegts",
		"avi":                     "avi",
		"":                        "",
	} {
		if got := NormalizeContainer(format); got != want {
			t.Errorf("%q → %q, want %q", format, got, want)
		}
	}
}
