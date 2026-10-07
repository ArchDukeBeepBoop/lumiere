package store

import "testing"

func TestChaptersNamedForTheirPartBecomeSkipMarks(t *testing.T) {
	const s = 10_000_000
	chapters := []Chapter{
		{StartTicks: 0, Name: "Prologue"},
		{StartTicks: 90 * s, Name: "OP"},
		{StartTicks: 180 * s, Name: "Part A"},
		{StartTicks: 1300 * s, Name: "Ending"},
		{StartTicks: 1390 * s, Name: "Preview"},
	}
	got := ChapterSegments("ep", chapters, 1420*s)
	if len(got) != 3 || got[2].Type != "Preview" {
		t.Fatalf("got %+v, want an intro, an outro and the preview", got)
	}
	if got[0].Type != "Intro" || got[0].StartTicks != 90*s || got[0].EndTicks != 180*s {
		t.Errorf("intro = %+v", got[0])
	}
	if got[1].Type != "Outro" || got[1].StartTicks != 1300*s || got[1].EndTicks != 1390*s {
		t.Errorf("outro = %+v", got[1])
	}
	if only := OnlyTypes(got, []string{"outro"}); len(only) != 1 || only[0].Type != "Outro" {
		t.Errorf("filter = %+v", only)
	}
	// "Episode" and "Opening Night" are not openings.
	if n := ChapterSegments("ep", []Chapter{{Name: "Opening Night"}, {StartTicks: s, Name: "Episode"}}, 2*s); len(n) != 0 {
		t.Errorf("ordinary chapter names became marks: %+v", n)
	}
}

func TestChaptersFillOnlyTheTypesTheAnalysisLacks(t *testing.T) {
	const s = 10_000_000
	have := []Segment{{Type: "Intro", StartTicks: 60 * s, EndTicks: 150 * s}}
	chapters := ChapterSegments("ep", []Chapter{
		{StartTicks: 0, Name: "Recap"}, {StartTicks: 55 * s, Name: "OP"},
		{StartTicks: 145 * s, Name: "Part A"}, {StartTicks: 1380 * s, Name: "Preview"},
	}, 1420*s)
	got := FillMissingTypes(have, chapters)
	kinds := map[string]int{}
	for _, g := range got {
		kinds[g.Type]++
	}
	if kinds["Intro"] != 1 || kinds["Recap"] != 1 || kinds["Preview"] != 1 {
		t.Errorf("kinds = %v, want the analysed intro kept and a recap and preview added", kinds)
	}
	if got[0].StartTicks != 60*s {
		t.Error("the chapter intro replaced the analysed one")
	}
}

func TestOnlyBelievableChapterMarksAreKept(t *testing.T) {
	const s = 10_000_000
	run := int64(1420 * s)
	for _, c := range []struct {
		kind       string
		start, end int64
		want       bool
	}{
		{"Recap", 0, 90 * s, true},
		{"Recap", 0, 4715 * s, false},       // the 78-minute "recap"
		{"Recap", 900 * s, 1000 * s, false}, // a recap in the second half
		{"Preview", 1390 * s, 1415 * s, true},
		{"Preview", 50 * s, 1414 * s, false},   // the 23-minute "preview"
		{"Preview", 1410 * s, 1412 * s, false}, // two seconds: a flicker
		{"Intro", 60 * s, 150 * s, true},
	} {
		if got := Believable(c.kind, c.start, c.end, run); got != c.want {
			t.Errorf("%s %d–%d s: %v, want %v", c.kind, c.start/s, c.end/s, got, c.want)
		}
	}
}
