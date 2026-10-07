package store

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Subtitle files kept beside a video rather than inside it — an MP4 with no
// subtitle track and an .srt in its folder is the common case.
//
// Found when the item is opened, not by the scanner: a folder listing is a few
// milliseconds, the answer is always current, and a subtitle dropped in later
// appears the next time the title is opened. What is found is recorded as an
// external Subtitle stream, the same row a downloaded subtitle gets, which the
// subtitle route already serves.

var subtitleExts = map[string]bool{".srt": true, ".ass": true, ".ssa": true, ".vtt": true}

var videoExts = map[string]bool{".mp4": true, ".m4v": true, ".mkv": true, ".avi": true, ".mov": true,
	".wmv": true, ".ts": true, ".m2ts": true, ".webm": true, ".mpg": true, ".mpeg": true}

// SidecarSubtitles lists the subtitle files that belong to a video:
//   - in its folder, named after it ("Film.mp4" → "Film.en.srt");
//   - in its folder at all, when it is the only video there;
//   - in a "Subs" or "Subtitles" folder beside it — directly, when it is the
//     only video, or in a subfolder named after it ("Subs/Show S01E02/2_English.srt").
//
// Pure apart from reading the folders, so the rules are tested on a temp tree.
func SidecarSubtitles(videoPath string) []string {
	dir := filepath.Dir(videoPath)
	base := strings.TrimSuffix(filepath.Base(videoPath), filepath.Ext(videoPath))
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	videos := 0
	for _, e := range entries {
		if !e.IsDir() && videoExts[strings.ToLower(filepath.Ext(e.Name()))] {
			videos++
		}
	}
	alone := videos <= 1
	var found []string
	add := func(p string) { found = append(found, p) }
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() {
			if l := strings.ToLower(name); l == "subs" || l == "subtitles" || l == "sub" {
				sub := filepath.Join(dir, name)
				if alone {
					for _, f := range subtitleFiles(sub) {
						add(f)
					}
				}
				for _, f := range subtitleFiles(filepath.Join(sub, base)) {
					add(f)
				}
			}
			continue
		}
		if !subtitleExts[strings.ToLower(filepath.Ext(name))] {
			continue
		}
		if alone || strings.HasPrefix(strings.ToLower(name), strings.ToLower(base)+".") ||
			strings.HasPrefix(strings.ToLower(name), strings.ToLower(base)+"_") {
			add(filepath.Join(dir, name))
		}
	}
	sort.Strings(found)
	if len(found) > 30 {
		found = found[:30]
	}
	return found
}

func subtitleFiles(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if !e.IsDir() && subtitleExts[strings.ToLower(filepath.Ext(e.Name()))] {
			out = append(out, filepath.Join(dir, e.Name()))
		}
	}
	return out
}

var languageNames = map[string]string{
	"english": "eng", "en": "eng", "eng": "eng", "french": "fre", "fr": "fre", "fre": "fre", "fra": "fre",
	"spanish": "spa", "es": "spa", "spa": "spa", "german": "ger", "de": "ger", "ger": "ger", "deu": "ger",
	"italian": "ita", "it": "ita", "ita": "ita", "japanese": "jpn", "ja": "jpn", "jpn": "jpn",
	"portuguese": "por", "pt": "por", "por": "por", "chinese": "chi", "zh": "chi", "chi": "chi", "zho": "chi",
	"korean": "kor", "ko": "kor", "kor": "kor", "russian": "rus", "ru": "rus", "rus": "rus",
	"arabic": "ara", "ar": "ara", "ara": "ara", "dutch": "dut", "nl": "dut", "dut": "dut",
}

// SidecarLanguage reads a language from a subtitle's file name — "Film.en.srt",
// "Film.English.forced.srt", "2_English.srt" — and keeps the rest as its title.
func SidecarLanguage(path string) (language, title string) {
	stem := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	parts := strings.FieldsFunc(stem, func(r rune) bool { return r == '.' || r == '_' || r == '-' || r == ' ' })
	for i := len(parts) - 1; i >= 0; i-- {
		if code, ok := languageNames[strings.ToLower(parts[i])]; ok {
			language = code
			break
		}
	}
	for _, p := range parts {
		switch strings.ToLower(p) {
		case "forced":
			title = "Forced"
		case "sdh", "cc":
			title = "SDH"
		}
	}
	if language == "" && title == "" {
		title = stem
	}
	return language, title
}

// LinkSidecarSubtitles records the sidecars not yet known for an item, and says
// whether it added any.
func (s *Store) LinkSidecarSubtitles(itemID, videoPath string, known []Stream) bool {
	have := map[string]bool{}
	for _, st := range known {
		if st.Path != "" {
			have[st.Path] = true
		}
	}
	added := false
	for _, p := range SidecarSubtitles(videoPath) {
		if have[p] {
			continue
		}
		language, title := SidecarLanguage(p)
		if _, err := s.AddExternalSubtitle(itemID, p, language, title); err == nil {
			added = true
		}
	}
	return added
}
