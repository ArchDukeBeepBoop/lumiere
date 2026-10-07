package api

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"lumiere-server/internal/store"
)

// Stream is GET /Videos/{id}/stream — roughly all of the real traffic.
//
// The whole job is to hand back the original file with honest HTTP range
// support. http.ServeContent does that correctly and there is no reason to
// hand-roll it: it answers open-ended ranges, ranges that end at EOF, a
// two-byte probe at the start, If-Range, HEAD, and it sets Accept-Ranges and
// Content-Range without being asked.
//
// The shape of real traffic is unusual enough to be worth naming, because a
// server that only streams forward from an offset passes a casual test and then
// hangs in the field. One playback made four requests, every one of them
// open-ended, and the second read the **last 33 KB of the file** — that is mpv
// fetching the Matroska cues from the tail before it will play anything. Expect
// several concurrent readers on one file, at unrelated offsets.
func (h PlaybackHandler) Stream(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		http.NotFound(w, r)
		return
	}
	item, err := h.Store.ItemByID(id)
	if err != nil {
		if !errors.Is(err, store.ErrNoItem) {
			h.Log.Error("stream lookup failed", "error", err, "item", id)
		}
		http.NotFound(w, r)
		return
	}
	if item.Path == "" || item.IsFolder {
		http.NotFound(w, r)
		return
	}

	f, err := os.Open(item.Path)
	if err != nil {
		// The database says there is a file and the disk disagrees: media moved
		// or a volume is not mounted. Worth an error line — both servers break
		// together on this, and only one of them has a rescanner.
		h.Log.Error("media file unreadable", "error", err, "item", id)
		http.Error(w, "media file is not readable", http.StatusNotFound)
		return
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		h.Log.Error("cannot stat media file", "error", err, "item", id)
		http.Error(w, "media file is not readable", http.StatusInternalServerError)
		return
	}

	// A real container MIME, not octet-stream. mpv and AVPlayer both sniff, but
	// the capture shows Jellyfin sending video/x-matroska and being honest
	// costs nothing.
	w.Header().Set("Content-Type", containerMIME(item.Container, item.Path))
	// Media is never cached by the client and re-requested constantly at
	// different offsets; saying so keeps an intermediary from trying.
	w.Header().Set("Cache-Control", "no-store")

	http.ServeContent(w, r, filepath.Base(item.Path), info.ModTime(), f)
}

// containerMIME maps a container to its type, preferring what the database
// recorded and falling back to the extension.
func containerMIME(container, path string) string {
	name := strings.ToLower(strings.TrimSpace(container))
	if name == "" {
		name = strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
	}
	switch name {
	case "mkv", "matroska", "matroska,webm":
		return "video/x-matroska"
	case "mp4", "m4v", "mov", "qt", "mov,mp4,m4a,3gp,3g2,mj2":
		return "video/mp4"
	case "webm":
		return "video/webm"
	case "avi":
		return "video/x-msvideo"
	case "ts", "m2ts", "mpegts":
		return "video/mp2t"
	case "flv":
		return "video/x-flv"
	case "wmv", "asf":
		return "video/x-ms-wmv"
	case "ogv", "ogg":
		return "video/ogg"
	case "mp3":
		return "audio/mpeg"
	case "flac":
		return "audio/flac"
	case "m4a", "aac":
		return "audio/mp4"
	case "opus":
		return "audio/opus"
	}
	return "application/octet-stream"
}

// NoEncoder answers the remux and transcode routes.
//
// 503 with a body that names the reason, which is a deliberate design decision
// rather than an unimplemented stub: this server has no encoder and will not
// grow one. The body matters because the only way a user reaches here is by
// setting a bitrate cap — the cap is the sole trigger for a server transcode in
// practice — and the message has to be plain enough that they know to clear it.
//
// 503 rather than 501: the client treats it as a transient failure of this
// playback rather than a permanent fact about the server, which is the more
// useful behaviour when the fix is a setting the user can change.
func (h PlaybackHandler) NoEncoder(w http.ResponseWriter, r *http.Request) {
	h.Log.Warn("refused an encode", "path", r.URL.Path,
		"bitrate_cap", r.URL.Query().Get("maxStreamingBitrate"))
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusServiceUnavailable)
	_, _ = w.Write([]byte(`{"Message":"This server does not transcode or remux. ` +
		`Clear the bitrate cap in Settings to play this file directly."}` + "\n"))
}

// Subtitle is GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.{ext}.
//
// Only external subtitles come through here: an in-band track travels inside
// the container and mpv reads it directly. 396 streams in this library are
// external, which is 0.2% — small enough to overlook and large enough that
// overlooking it means a handful of files silently play with no subtitles at
// all, which reads as a broken file rather than a missing route.
//
// The extension in the URL names the format the client wants. This server does
// not convert between subtitle formats, so it serves the file it has and lets
// the extension be advisory; mpv sniffs the content regardless.
func (h PlaybackHandler) Subtitle(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	index := atoiOr(r.PathValue("index"), -1)
	if id == "" || index < 0 {
		http.NotFound(w, r)
		return
	}
	streams, err := h.Store.Streams(id)
	if err != nil {
		h.Log.Error("subtitle lookup failed", "error", err, "item", id)
		http.NotFound(w, r)
		return
	}
	for _, st := range streams {
		if st.Index != index {
			continue
		}
		if st.Path == "" {
			// An in-band track. Answering 404 is right: there is no file to
			// send, and the client already has the track inside the container.
			break
		}
		f, err := os.Open(st.Path)
		if err != nil {
			h.Log.Warn("external subtitle unreadable", "error", err, "item", id)
			break
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil {
			break
		}
		w.Header().Set("Content-Type", subtitleMIME(st.Path))
		http.ServeContent(w, r, filepath.Base(st.Path), info.ModTime(), f)
		return
	}
	http.NotFound(w, r)
}

func subtitleMIME(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".srt":
		return "application/x-subrip"
	case ".vtt":
		return "text/vtt"
	case ".ass", ".ssa":
		return "text/x-ssa"
	}
	return "text/plain; charset=utf-8"
}
