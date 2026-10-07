package store

import (
	"os"
	"path/filepath"
	"testing"
)

func touch(t *testing.T, p string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestSidecarsBesideALoneFilm(t *testing.T) {
	dir := t.TempDir()
	film := filepath.Join(dir, "Film (2010)", "film.mp4")
	touch(t, film)
	touch(t, filepath.Join(dir, "Film (2010)", "English.srt"))
	touch(t, filepath.Join(dir, "Film (2010)", "Subs", "fr.srt"))
	if got := SidecarSubtitles(film); len(got) != 2 {
		t.Fatalf("want both subtitles for the only film in its folder, got %v", got)
	}
}

func TestSidecarsAmongEpisodesMatchByName(t *testing.T) {
	dir := t.TempDir()
	e1 := filepath.Join(dir, "Show S01E01.mp4")
	touch(t, e1)
	touch(t, filepath.Join(dir, "Show S01E02.mp4"))
	touch(t, filepath.Join(dir, "Show S01E01.en.srt"))
	touch(t, filepath.Join(dir, "Show S01E02.en.srt"))
	touch(t, filepath.Join(dir, "Subs", "Show S01E01", "2_English.srt"))
	got := SidecarSubtitles(e1)
	if len(got) != 2 {
		t.Fatalf("want E01's own two subtitles, got %v", got)
	}
}

func TestSidecarLanguageFromNames(t *testing.T) {
	for name, want := range map[string]string{"Film.en.srt": "eng", "2_English.srt": "eng", "Film.French.forced.ass": "fre"} {
		if got, _ := SidecarLanguage(name); got != want {
			t.Errorf("%s: got %q, want %q", name, got, want)
		}
	}
	if _, title := SidecarLanguage("Film.English.forced.srt"); title != "Forced" {
		t.Errorf("forced not noted: %q", title)
	}
}
