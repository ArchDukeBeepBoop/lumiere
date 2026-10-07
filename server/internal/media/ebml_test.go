package media

import (
	"os"
	"testing"
)

// Against the release that started this: Buso Renkin links its opening and
// ending to segments that are not in the folder. Skipped where the file is
// not present.
func TestReadSegmentFollowsOrderedChapters(t *testing.T) {
	path := os.Getenv("LUMIERE_LINKED_SAMPLE")
	if path == "" {
		path = "/Volumes/Media/Anime/Buso Renkin/Season 1/Buso Renkin - 1x01 - A New Life.mkv"
	}
	if _, err := os.Stat(path); err != nil {
		t.Skip("no linked sample on this machine")
	}
	seg, err := ReadSegment(path)
	if err != nil {
		t.Fatal(err)
	}
	if seg.UID != "f47f7c02963a35281163c981f59a12f7" {
		t.Errorf("uid %s", seg.UID)
	}
	if !seg.Ordered || len(seg.Chapters) != 4 {
		t.Fatalf("ordered %v, %d chapters", seg.Ordered, len(seg.Chapters))
	}
	if seg.Chapters[0].LinkUID != "b12812d01debfc51b2892f546cf89d8c" || seg.Chapters[0].Title != "Opening" {
		t.Errorf("opening = %+v", seg.Chapters[0])
	}
	if seg.Chapters[1].LinkUID != "" || seg.Chapters[1].Title != "Episode" {
		t.Errorf("episode = %+v", seg.Chapters[1])
	}
	if seg.Chapters[2].LinkUID != "353f6e9336d63a157d3688637855bd80" {
		t.Errorf("ending = %+v", seg.Chapters[2])
	}
}

func TestReadSegmentOnAPlainFile(t *testing.T) {
	path := "/Volumes/Media/Anime/Aquarion/Season 2 - Evol/Aquarion EVOL - 1x01 - A Myth That Holds An End.mkv"
	if _, err := os.Stat(path); err != nil {
		t.Skip("no sample")
	}
	seg, err := ReadSegment(path)
	if err != nil {
		t.Fatal(err)
	}
	if seg.UID == "" || seg.Ordered || len(seg.Chapters) != 0 {
		t.Errorf("plain file read as %+v", seg)
	}
}
