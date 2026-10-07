package api

import "testing"

func TestLRCSortsRepeatsAndDropsDoubledCopies(t *testing.T) {
	_, lines := ParseLRC("[ar:2Pac]\n[00:09.43]Me against the world\n[00:13.84]Nothin' to lose\n" +
		"[00:09.43]Me against the world\n[01:00.00][00:20.5]Chorus\n")
	if len(lines) != 4 {
		t.Fatalf("%d lines", len(lines))
	}
	if lines[0].Text != "Me against the world" || *lines[0].Start != 94_300_000 {
		t.Errorf("%+v", lines[0])
	}
	if lines[2].Text != "Chorus" || *lines[3].Start != 600_000_000 {
		t.Errorf("a chorus belongs at each of its times: %+v %+v", lines[2], lines[3])
	}
}

func TestPlainLyricsStayUntimed(t *testing.T) {
	_, lines := ParseLRC("\nFirst\nSecond\n\n")
	if len(lines) != 2 || lines[0].Start != nil {
		t.Errorf("%+v", lines)
	}
}
