package scanner

import (
	"context"
	"encoding/json"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// A file's tracks, read by this server rather than waited for from Jellyfin.
//
// Only the import ever recorded tracks, so the 1,066 files the scanner found
// itself had none — no audio or subtitle names in any player, and nothing for
// a TV to check its decoders against before playing. Ted Lasso 4x09 was one:
// Atmos audio a projector cannot decode, and nothing to say so.

// ProbeStreams reads every track of one file.
func ProbeStreams(tool, path string) ([]store.ProbedStream, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, tool, "-v", "quiet", "-print_format", "json",
		"-show_streams", path).Output()
	if err != nil {
		return nil, err
	}
	return ParseStreams(out)
}

// ParseStreams is ffprobe's -show_streams answer as stream rows. Pure.
func ParseStreams(output []byte) ([]store.ProbedStream, error) {
	var raw struct {
		Streams []struct {
			Index         int               `json:"index"`
			CodecType     string            `json:"codec_type"`
			CodecName     string            `json:"codec_name"`
			Profile       string            `json:"profile"`
			Width         int               `json:"width"`
			Height        int               `json:"height"`
			PixFmt        string            `json:"pix_fmt"`
			ColorTransfer string            `json:"color_transfer"`
			Channels      int               `json:"channels"`
			Layout        string            `json:"channel_layout"`
			SampleRate    string            `json:"sample_rate"`
			BitRate       string            `json:"bit_rate"`
			FrameRate     string            `json:"avg_frame_rate"`
			Disposition   map[string]int    `json:"disposition"`
			Tags          map[string]string `json:"tags"`
		} `json:"streams"`
	}
	if err := json.Unmarshal(output, &raw); err != nil {
		return nil, err
	}
	var rows []store.ProbedStream
	for _, s := range raw.Streams {
		kind := map[string]string{"video": "Video", "audio": "Audio", "subtitle": "Subtitle", "attachment": "Attachment"}[s.CodecType]
		if kind == "" || kind == "Attachment" || (kind == "Video" && s.Disposition["attached_pic"] == 1) {
			continue
		}
		r := store.ProbedStream{
			Index: s.Index, Type: kind, Codec: s.CodecName, Profile: s.Profile,
			Language: s.Tags["language"], Title: s.Tags["title"],
			Default: s.Disposition["default"] == 1, Forced: s.Disposition["forced"] == 1,
			Width: s.Width, Height: s.Height, Channels: s.Channels, Layout: s.Layout,
		}
		r.SampleRate, _ = strconv.Atoi(s.SampleRate)
		r.BitRate, _ = strconv.ParseInt(s.BitRate, 10, 64)
		if kind == "Video" {
			r.BitDepth = 8
			if strings.Contains(s.PixFmt, "10") {
				r.BitDepth = 10
			} else if strings.Contains(s.PixFmt, "12") {
				r.BitDepth = 12
			}
			r.Range = "SDR"
			if s.ColorTransfer == "smpte2084" || s.ColorTransfer == "arib-std-b67" {
				r.Range = "HDR"
			}
			if num, den, ok := strings.Cut(s.FrameRate, "/"); ok {
				n, _ := strconv.ParseFloat(num, 64)
				d, _ := strconv.ParseFloat(den, 64)
				if d > 0 {
					r.FrameRate = n / d
				}
			}
		}
		rows = append(rows, r)
	}
	return rows, nil
}

// FillStreams probes up to limit files that have no tracks recorded, newest
// first. Returns how many it filled.
func FillStreams(db *store.Store, limit int) int {
	tool := FindFFprobe()
	if tool == "" {
		return 0
	}
	filled := 0
	for _, c := range db.ItemsWithoutStreams(limit) {
		rows, err := ProbeStreams(tool, c.Path)
		if err != nil || len(rows) == 0 {
			db.SetItemValue(c.ID, "streams:failed", "1")
			continue
		}
		if db.WriteStreams(c.ID, rows) == nil {
			filled++
		}
	}
	return filled
}
