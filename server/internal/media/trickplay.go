package media

import (
	"context"
	"encoding/json"
	"fmt"
	"image"
	_ "image/jpeg"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// Scrubbing previews, made here.
//
// The client has always drawn Jellyfin's trickplay sheets — a grid of small
// frames, one every ten seconds, that follows the pointer along the scrub bar —
// but Jellyfin never made any for this library, and this server made none
// either, so every scrub showed a bare timecode. These are the same sheets in
// the same layout, so the client's existing drawing code needs nothing new.

// Trickplay layout: Jellyfin's defaults, which the client was built against.
const (
	TrickplayWidth    = 320
	trickplayTiles    = 10 // a sheet is 10×10 frames
	trickplayInterval = 10 // seconds between frames
)

// TrickplayInfo is what an item's detail carries, keyed by width. Field names
// are Jellyfin's.
type TrickplayInfo struct {
	Width          int
	Height         int
	TileWidth      int
	TileHeight     int
	ThumbnailCount int
	Interval       int
	Bandwidth      int
	// Fingerprint is the file's size:mtime the sheets were made from, so an
	// edited file gets new ones. Not sent to clients.
	Fingerprint string `json:"-"`
}

// trickplayRecord is the item_value form, which keeps the fingerprint.
type trickplayRecord struct {
	TrickplayInfo
	FP string
}

// EncodeTrickplay and DecodeTrickplay move the record in and out of item_value.
func EncodeTrickplay(info TrickplayInfo) string {
	raw, _ := json.Marshal(trickplayRecord{info, info.Fingerprint})
	return string(raw)
}

func DecodeTrickplay(raw string) (TrickplayInfo, bool) {
	var r trickplayRecord
	if raw == "" || json.Unmarshal([]byte(raw), &r) != nil || r.ThumbnailCount == 0 {
		return TrickplayInfo{}, false
	}
	r.TrickplayInfo.Fingerprint = r.FP
	return r.TrickplayInfo, true
}

// TrickplayDir is where one item's sheets live: <dir>/<id>/320/<n>.jpg.
func TrickplayDir(root, itemID string) string {
	return filepath.Join(root, itemID, fmt.Sprint(TrickplayWidth))
}

// MakeTrickplay writes the sheets for one video and describes them.
//
// Keyframes only (-skip_frame nokey): the frame nearest each ten-second mark
// rather than the exact one, at a small fraction of the cost of decoding every
// frame — Jellyfin's own "key frame only" option, and the difference cannot be
// seen in a 320-pixel thumbnail. niced and held to two threads, and bounded at
// twenty minutes so one bad file cannot hold the queue.
func MakeTrickplay(ffmpeg, video string, runtimeSeconds float64, dir string) (TrickplayInfo, error) {
	if runtimeSeconds <= 0 {
		return TrickplayInfo{}, fmt.Errorf("no runtime")
	}
	os.RemoveAll(dir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return TrickplayInfo{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	defer cancel()
	filter := fmt.Sprintf("fps=1/%d,scale=%d:-2,tile=%dx%d",
		trickplayInterval, TrickplayWidth, trickplayTiles, trickplayTiles)
	command := exec.CommandContext(ctx, "nice", "-n", "15", ffmpeg,
		"-v", "error", "-y", "-threads", "2",
		"-skip_frame", "nokey", "-i", video,
		"-an", "-sn", "-vf", filter,
		"-strict", "unofficial", "-q:v", "5",
		"-start_number", "0", filepath.Join(dir, "%d.jpg"))
	if output, err := command.CombinedOutput(); err != nil {
		os.RemoveAll(dir)
		return TrickplayInfo{}, fmt.Errorf("ffmpeg: %w: %.300s", err, output)
	}
	first, err := os.Open(filepath.Join(dir, "0.jpg"))
	if err != nil {
		os.RemoveAll(dir)
		return TrickplayInfo{}, fmt.Errorf("ffmpeg wrote no sheets")
	}
	defer first.Close()
	sheet, _, err := image.DecodeConfig(first)
	if err != nil {
		return TrickplayInfo{}, err
	}
	count := int(runtimeSeconds) / trickplayInterval
	if count < 1 {
		count = 1
	}
	// Never more frames than the sheets hold: a file shorter than its header
	// says stops early, and the client must not ask for a sheet past the end.
	sheets, _ := filepath.Glob(filepath.Join(dir, "*.jpg"))
	if most := len(sheets) * trickplayTiles * trickplayTiles; count > most {
		count = most
	}
	return TrickplayInfo{
		Width: TrickplayWidth, Height: sheet.Height / trickplayTiles,
		TileWidth: trickplayTiles, TileHeight: trickplayTiles,
		ThumbnailCount: count, Interval: trickplayInterval * 1000,
		Bandwidth:   sheet.Width * sheet.Height / 8,
		Fingerprint: videoFingerprint(video),
	}, nil
}

// VideoFingerprint is size:mtime, exported for the scheduler's staleness check.
func VideoFingerprint(path string) string { return videoFingerprint(path) }
