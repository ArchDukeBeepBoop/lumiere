package store

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAMisfiledEpisodeMovesToItsSeasonWithItsSubtitles(t *testing.T) {
	show := filepath.Join(t.TempDir(), "Aristocrat")
	s1 := filepath.Join(show, "Season 01 - Beginnings")
	s2 := filepath.Join(show, "Season 2")
	os.MkdirAll(s1, 0o755)
	os.MkdirAll(s2, 0o755)
	video := filepath.Join(s2, "Aristocrat - S01E20.mkv")
	os.WriteFile(video, []byte("v"), 0o644)
	os.WriteFile(filepath.Join(s2, "Aristocrat - S01E20.en.srt"), []byte("s"), 0o644)
	os.WriteFile(filepath.Join(s2, "Aristocrat - S02E01.mkv"), []byte("other"), 0o644)
	os.WriteFile(filepath.Join(s2, "Aristocrat - S01E200.mkv"), []byte("longer name"), 0o644)

	folder, err := SeasonFolderFor(video, 1)
	if err != nil || folder != s1 {
		t.Fatalf("folder = %q (%v), want the existing season 1 folder", folder, err)
	}
	moves, err := MoveWithSidecars(video, folder)
	if err != nil || len(moves) != 2 {
		t.Fatalf("moves = %+v (%v), want the video and its subtitle", moves, err)
	}
	if _, err := os.Stat(filepath.Join(s1, "Aristocrat - S01E20.en.srt")); err != nil {
		t.Error("the subtitle did not go with it")
	}
	if _, err := os.Stat(filepath.Join(s2, "Aristocrat - S01E200.mkv")); err != nil {
		t.Error("a file whose name merely starts the same was moved")
	}
	if _, err := os.Stat(filepath.Join(s2, "Aristocrat - S02E01.mkv")); err != nil {
		t.Error("a correctly filed neighbour was moved")
	}
	// No season 3 folder: one is made, plainly named.
	if f, _ := SeasonFolderFor(filepath.Join(s2, "x - S03E01.mkv"), 3); f != filepath.Join(show, "Season 3") {
		t.Errorf("new folder = %q", f)
	}
}
