package scanner

import (
	"testing"

	"lumiere-server/internal/store"
)

func TestChaptersFromAFileBecomeSkipMarks(t *testing.T) {
	probe := []byte(`{"format": {"format_name": "matroska,webm", "duration": "1440"},
		"chapters": [
			{"start_time": "0.000000", "tags": {"title": "Prologue"}},
			{"start_time": "90.000000", "tags": {"title": "Opening"}},
			{"start_time": "180.000000", "tags": {"title": "Part A"}},
			{"start_time": "1320.000000", "tags": {"title": "Ending"}},
			{"start_time": "1410.000000", "tags": {"title": "Preview"}}]}`)
	p, err := parseProbe(probe)
	if err != nil || len(p.Chapters) != 5 || p.Chapters[1].Name != "Opening" || p.Chapters[1].StartSeconds != 90 {
		t.Fatalf("chapters: %+v %v", p.Chapters, err)
	}
	s := testScanner(t)
	writeChapters(s.Store.DB, "ep", p.Chapters)
	chapters, err := s.Store.Chapters("ep")
	if err != nil || len(chapters) != 5 {
		t.Fatalf("stored: %d %v", len(chapters), err)
	}
	marks := store.ChapterSegments("ep", chapters, 1440*10_000_000)
	kinds := map[string]bool{}
	for _, m := range marks {
		kinds[m.Type] = true
	}
	if !kinds["Intro"] || !kinds["Outro"] {
		t.Fatalf("Skip Intro and Skip Credits come from the chapter names: %+v", marks)
	}
}
