package api

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"lumiere-server/internal/store"
)

// Lyrics from the file beside a track, in Jellyfin's shape.
//
// GET  /Audio/{id}/Lyrics  {"Metadata": {...}, "Lyrics": [{"Text", "Start"}]}
// POST /Audio/{id}/Lyrics?fileName=lyrics.lrc  the text, saved beside the track
//
// A .lrc beside the track — same name, different extension — is how nearly
// every tagger and downloader leaves synced lyrics, and 1,017 tracks here
// have one. A .txt is read the same way, unsynced.
type LyricsHandler struct {
	Store *store.Store
}

type lyricLine struct {
	Text  string
	Start *int64 `json:",omitempty"`
}

func lyricsFile(track string) (string, bool) {
	base := strings.TrimSuffix(track, filepath.Ext(track))
	for _, ext := range []string{".lrc", ".LRC", ".txt"} {
		if _, err := os.Stat(base + ext); err == nil {
			return base + ext, true
		}
	}
	return base + ".lrc", false
}

func (h LyricsHandler) Get(w http.ResponseWriter, r *http.Request) {
	item, err := h.Store.ItemByID(store.NormalizeID(r.PathValue("id")))
	if err != nil || item.Path == "" {
		http.NotFound(w, r)
		return
	}
	path, ok := lyricsFile(item.Path)
	raw, err := os.ReadFile(path)
	if !ok || err != nil {
		http.NotFound(w, r)
		return
	}
	meta, lines := ParseLRC(string(raw))
	if len(lines) == 0 {
		http.NotFound(w, r)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"Metadata": meta, "Lyrics": lines})
}

// Post saves lyrics beside the track. An existing file is replaced only by
// what was sent, and a .lrc is kept a .lrc.
func (h LyricsHandler) Post(w http.ResponseWriter, r *http.Request) {
	item, err := h.Store.ItemByID(store.NormalizeID(r.PathValue("id")))
	if err != nil || item.Path == "" {
		http.NotFound(w, r)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"lyrics too large"})
		return
	}
	path, _ := lyricsFile(item.Path)
	if _, lines := ParseLRC(string(body)); len(lines) > 0 && lines[0].Start == nil {
		path = strings.TrimSuffix(path, filepath.Ext(path)) + ".txt"
	}
	if err := os.WriteFile(path, body, 0o644); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save beside the track"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

var (
	lrcTime = regexp.MustCompile(`\[(\d+):(\d+(?:[.:]\d+)?)\]`)
	lrcTag  = regexp.MustCompile(`^\[([a-zA-Z]+):(.*)\]$`)
)

// ParseLRC reads synced or plain lyrics. A line with several stamps — a
// chorus written once — is placed at each; lines are sorted by time and a
// file played twice over (some downloaders write the lyrics twice) keeps one
// copy of each moment. Plain text comes back as untimed lines.
func ParseLRC(text string) (map[string]string, []lyricLine) {
	meta := map[string]string{}
	var timed, plain []lyricLine
	seen := map[string]bool{}
	for _, row := range strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n") {
		row = strings.TrimSpace(strings.TrimPrefix(row, "\uFEFF"))
		stamps := lrcTime.FindAllStringSubmatch(row, -1)
		if len(stamps) == 0 {
			if m := lrcTag.FindStringSubmatch(row); m != nil {
				meta[strings.ToLower(m[1])] = strings.TrimSpace(m[2])
				continue
			}
			plain = append(plain, lyricLine{Text: row})
			continue
		}
		words := strings.TrimSpace(lrcTime.ReplaceAllString(row, ""))
		for _, s := range stamps {
			minutes, _ := strconv.Atoi(s[1])
			seconds, _ := strconv.ParseFloat(strings.Replace(s[2], ":", ".", 1), 64)
			ticks := int64((float64(minutes)*60 + seconds) * 10_000_000)
			key := strconv.FormatInt(ticks, 10) + "|" + words
			if seen[key] {
				continue
			}
			seen[key] = true
			timed = append(timed, lyricLine{Text: words, Start: &ticks})
		}
	}
	if len(timed) > 0 {
		sort.SliceStable(timed, func(i, j int) bool { return *timed[i].Start < *timed[j].Start })
		return meta, timed
	}
	for len(plain) > 0 && plain[len(plain)-1].Text == "" {
		plain = plain[:len(plain)-1]
	}
	for len(plain) > 0 && plain[0].Text == "" {
		plain = plain[1:]
	}
	return meta, plain
}
