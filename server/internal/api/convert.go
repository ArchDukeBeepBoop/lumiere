package api

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os/exec"
	"strconv"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
)

// ConvertHandler is GET /Videos/{id}/aac.mkv?start=SECONDS&audio=INDEX: the
// file with its picture and subtitles untouched and only the chosen audio
// track turned into AAC, for a TV that cannot decode the original — Dolby
// Atmos, TrueHD, DTS. The first time this server converts anything, and the
// lightest kind there is: the video is copied, so the Mac does a few percent
// of one core's work rather than an encode.
//
// Streamed as it is made, so it cannot be seeked within; the player asks
// again from the new point (start=) instead, and adds the offset itself.
type ConvertHandler struct {
	Store *store.Store
	Log   *slog.Logger
}

func (h ConvertHandler) AAC(w http.ResponseWriter, r *http.Request) {
	item, err := h.Store.ItemByID(store.NormalizeID(r.PathValue("id")))
	if err != nil || item.Path == "" {
		http.NotFound(w, r)
		return
	}
	ffmpeg := media.FindFFmpeg()
	if ffmpeg == "" {
		writeJSON(w, http.StatusServiceUnavailable, errorBody{"no ffmpeg on this Mac"})
		return
	}
	start, _ := strconv.ParseFloat(r.URL.Query().Get("start"), 64)
	audio := "0:a:0"
	if idx, err := strconv.Atoi(r.URL.Query().Get("audio")); err == nil && idx >= 0 {
		audio = fmt.Sprintf("0:%d", idx)
	}
	args := []string{"-n", "10", ffmpeg, "-nostdin", "-v", "error",
		"-ss", fmt.Sprintf("%.3f", start), "-i", item.Path,
		"-map", "0:v:0", "-map", audio, "-map", "0:s?", "-map", "0:t?",
		"-c", "copy", "-c:a", "aac", "-b:a", "384k", "-threads", "2",
		"-f", "matroska", "pipe:1"}
	cmd := exec.CommandContext(r.Context(), "nice", args...)
	out, err := cmd.StdoutPipe()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not start"})
		return
	}
	if err := cmd.Start(); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not start"})
		return
	}
	h.Log.Info("converting audio for a device that cannot decode it", "item", item.ID, "from", start)
	w.Header().Set("Content-Type", "video/x-matroska")
	w.Header().Set("Cache-Control", "no-store")
	flusher, _ := w.(http.Flusher)
	buf := make([]byte, 256<<10)
	for {
		n, rerr := out.Read(buf)
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				break
			}
			if flusher != nil {
				flusher.Flush()
			}
		}
		if rerr == io.EOF || rerr != nil {
			break
		}
	}
	cmd.Wait()
}
