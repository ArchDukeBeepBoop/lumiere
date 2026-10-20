package store

import "testing"

func TestSubtitlePathCannotLeaveTheVideosFolder(t *testing.T) {
	got := ExternalSubtitlePath("/m/Show/ep1.mkv", "x/../../../../Library/LaunchAgents/evil", "srt")
	if got != "/m/Show/ep1.xLibraryLaunchAgent.srt" && (len(got) < 9 || got[:9] != "/m/Show/e") {
		t.Fatalf("escaped: %s", got)
	}
	for _, c := range got[len("/m/Show/"):] {
		if c == '/' {
			t.Fatalf("a slash survived: %s", got)
		}
	}
	if p := ExternalSubtitlePath("/m/Show/ep1.mkv", "pt-BR", "../ass"); p != "/m/Show/ep1.pt-BR.ass" {
		t.Fatalf("extension: %s", p)
	}
}
