package media

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// FindFFmpeg locates the encoder the same way the scanner locates ffprobe: the
// PATH first, then Homebrew's prefixes, because the menu-bar app that launches
// this server has no PATH to speak of.
func FindFFmpeg() string {
	if path, err := exec.LookPath("ffmpeg"); err == nil {
		return path
	}
	for _, path := range []string{
		// Jellyfin's bundled copy first, for the same reason as ffprobe.
		"/Applications/Jellyfin.app/Contents/MacOS/ffmpeg",
		"/opt/homebrew/bin/ffmpeg",
		"/usr/local/bin/ffmpeg",
		"/usr/local/opt/ffmpeg/bin/ffmpeg",
		"/opt/homebrew/opt/ffmpeg/bin/ffmpeg",
	} {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

// framePosition is how far into a file the frame is taken from.
//
// A fifth of the way, matching the app's own "Use Frame from File". Early
// enough to be past an opening, late enough to be past the studio cards.
const framePosition = 0.2

// ExtractFrame writes one JPEG from a video.
//
// 640 wide, which is more than a tile ever draws and a tenth of what a
// full-size grab would cost across a library of thousands. Bounded at thirty
// seconds: a file on a mount that has gone away must not hold the pass.
//
// Tried at a fifth of the way in, then at thirty seconds, then at five: a file
// shorter than its header says — a download cut off part-way, One Piece 222
// here — has no picture at a fifth of a length it does not have, and one
// failure there used to mean no picture at all.
func ExtractFrame(ffmpeg, video string, runtimeSeconds float64, out string) error {
	tries := []float64{30, 5}
	if runtimeSeconds > 0 {
		tries = []float64{runtimeSeconds * framePosition, 30, 5}
	}
	var last error
	for _, at := range tries {
		os.Remove(out)
		if last = extractAt(ffmpeg, video, at, out); last == nil {
			if info, err := os.Stat(out); err == nil && info.Size() > 0 {
				return nil
			}
			last = fmt.Errorf("ffmpeg wrote no picture at %.0fs", at)
		}
	}
	return last
}

func extractAt(ffmpeg, video string, at float64, out string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	command := exec.CommandContext(ctx, ffmpeg,
		"-v", "error", "-y",
		"-ss", fmt.Sprintf("%.2f", at),
		"-i", video,
		"-frames:v", "1",
		"-vf", "scale=640:-2",
		// A file whose colour is full-range YUV — some of the older rips
		// here — made ffmpeg refuse the JPEG encoder outright: "Non
		// full-range YUV is non-standard, set strict_std_compliance to at
		// most unofficial to use it." It is saying the picture is fine and
		// the standard is narrow, and that is its own advice for taking it
		// anyway. Without this those clips kept a blank tile for good.
		"-strict", "unofficial",
		"-q:v", "3",
		out)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg: %w: %s", err, string(output))
	}
	return nil
}

// Frames gives a picture to every file that has none.
//
// The last resort after the naming pass, which is why it runs after it rather
// than beside it: a scraped poster is better than a frame, and this only
// touches what the scrapers left bare. That is every file in a folder library
// — 3D and My Videos have no provider behind them by design — and every
// episode in a library the providers do not cover, which is most of an adult
// one. Those tiles were grey, and had been grey since the server stopped
// mirroring Jellyfin, which used to grab these frames itself.
//
// Bare means no Primary picture, not no picture at all. A tile draws the
// Primary and nothing else, so a clip carrying only a backdrop is a blank
// tile with a row in the database saying otherwise — one of these was the
// last blank left in My Videos after every missing file had been replaced.
//
// Idempotent: a file with a Primary that is actually on disk is skipped, so
// a poster fetched later is never overwritten and a re-run does nothing. A
// row pointing at a picture that is *not* there is treated as bare too — a
// file moved between folders outlives the frame taken of it at the old path.
func Frames(db *sql.DB, ffmpeg, imageDir string, limit int, log *slog.Logger) (int, error) {
	if ffmpeg == "" {
		return 0, nil
	}
	rows, err := db.Query(`
		SELECT id, path, COALESCE(runtime_ticks, 0) FROM item
		WHERE is_folder = 0 AND path IS NOT NULL AND path <> ''
		  AND type IN ('Video', 'Movie', 'Episode')
		  AND NOT EXISTS (
			SELECT 1 FROM image g WHERE g.item_id = item.id AND g.kind = 'Primary'
		  )
		ORDER BY date_created DESC
		LIMIT ?`, limit)

	if err != nil {
		return 0, err
	}

	var files []bare
	for rows.Next() {
		var f bare
		if err := rows.Scan(&f.id, &f.path, &f.ticks); err != nil {
			rows.Close()
			return 0, err
		}
		files = append(files, f)
	}
	rows.Close()

	// And the ones whose picture is a path that no longer resolves.
	stale, err := staleArtwork(db, limit)
	if err != nil {
		return 0, err
	}
	files = append(files, stale...)

	// And the ones whose video changed since their frame was taken. See
	// framecheck.go.
	changed, err := changedFrames(db, limit)
	if err != nil {
		return 0, err
	}
	files = append(files, changed...)

	made := 0
	for _, f := range files {
		fingerprint := videoFingerprint(f.path)
		if fingerprint == "" || failedBefore(db, f.id, fingerprint) {
			continue
		}
		out := filepath.Join(imageDir, "frames", f.id+".jpg")
		if err := ExtractFrame(ffmpeg, f.path, float64(f.ticks)/10_000_000, out); err != nil {
			// Said once per version of the file, then left alone until it
			// changes: the same broken download logged thirty-five times.
			log.Info("frames: could not extract", "path", f.path, "error", err)
			setFrameValue(db, f.id, "frame:failed", failureMark(fingerprint))
			continue
		}
		setFrameValue(db, f.id, "frame:source", fingerprint)
		setFrameValue(db, f.id, "frame:failed", "")
		sum := sha256.Sum256([]byte(out + time.Now().String()))
		tag := hex.EncodeToString(sum[:8])
		if _, err := db.Exec(`
			INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?, 'Primary', 0, ?, ?)
			ON CONFLICT(item_id, kind, idx) DO UPDATE SET path = excluded.path, tag = excluded.tag`,
			f.id, out, tag); err != nil {
			log.Info("frames: could not record", "id", f.id, "error", err)
			continue
		}
		made++
	}
	if made > 0 {
		log.Info("frames: pictures made for bare files", "count", made)
	}
	return made, nil
}
