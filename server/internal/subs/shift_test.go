package subs

import "testing"

func TestShiftMovesEveryTimestamp(t *testing.T) {
	srt := "1\n00:00:01,500 --> 00:00:03,000\nHello\n\n2\n00:59:59,900 --> 01:00:00,100\nBye\n"
	got, err := Shift([]byte(srt), "srt", 26.7)
	if err != nil {
		t.Fatal(err)
	}
	want := "1\n00:00:28,200 --> 00:00:29,700\nHello\n\n2\n01:00:26,600 --> 01:00:26,800\nBye\n"
	if string(got) != want {
		t.Errorf("srt shifted =\n%s\nwant\n%s", got, want)
	}
	ass := "Dialogue: 0,0:00:05.20,0:00:07.00,Default,,0,0,0,,Hi"
	got, _ = Shift([]byte(ass), "ass", -10)
	if string(got) != "Dialogue: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,,Hi" {
		t.Errorf("ass below zero = %s, want clamped at zero", got)
	}
	vtt := "00:00:02.000 --> 00:00:04.250"
	got, _ = Shift([]byte(vtt), "vtt", 1)
	if string(got) != "00:00:03.000 --> 00:00:05.250" {
		t.Errorf("vtt = %s", got)
	}
	if _, err := Shift([]byte("x"), "sup", 1); err == nil {
		t.Error("an image subtitle claimed to shift")
	}
}

func TestBestSkipsMachineTranslationsAndPrefersTrust(t *testing.T) {
	best, ok := Best([]Candidate{
		{FileID: 1, Downloads: 9000, Machine: true},
		{FileID: 2, Downloads: 500},
		{FileID: 3, Downloads: 100, FromTrust: true},
		{FileID: 4, Downloads: 300, FromTrust: true},
		{FileID: 5, Downloads: 99999, AI: true},
	})
	if !ok || best.FileID != 4 {
		t.Errorf("best = %d, want the most downloaded trusted one (4)", best.FileID)
	}
	if _, ok := Best([]Candidate{{FileID: 1, Machine: true}}); ok {
		t.Error("only machine translations should yield nothing")
	}
}
