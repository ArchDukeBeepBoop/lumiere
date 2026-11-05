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
	"strings"
	"time"
)

// Album covers, from the music itself.
//
// Jellyfin used to pull these out and the import kept them; a library put back
// without that import (2026-10-25) had 975 albums and not one cover, so every
// album tile, the artists drawn from their albums and the Music card on Home
// were blank. A cover image in the album's folder wins — cover.jpg, folder.jpg
// and the like are what the owner chose — and the picture embedded in the
// first track is the fallback, which is where most of this library keeps it.
//
// Idempotent: an album with a Primary is skipped, and one with no picture
// anywhere is marked `cover:none` so the next pass does not ask again.

var coverNames = []string{"cover", "folder", "front", "album", "albumart", "albumartsmall"}

// MusicCovers gives albums with no picture one; returns how many.
func MusicCovers(db *sql.DB, ffmpeg, imageDir string, limit int, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT a.id, COALESCE(a.path, ''),
		       COALESCE((SELECT t.path FROM item t WHERE t.parent_id = a.id AND t.type = 'Audio'
		                 AND COALESCE(t.path, '') <> '' ORDER BY t.parent_index_number, t.index_number LIMIT 1), '')
		FROM item a
		WHERE a.type = 'MusicAlbum'
		  AND NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = a.id AND g.kind = 'Primary')
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = a.id AND v.kind = 'cover:none')
		LIMIT ?`, limit)
	if err != nil {
		return 0, err
	}
	type album struct{ id, folder, track string }
	var albums []album
	for rows.Next() {
		var a album
		if err := rows.Scan(&a.id, &a.folder, &a.track); err != nil {
			rows.Close()
			return 0, err
		}
		albums = append(albums, a)
	}
	rows.Close()

	made := 0
	for _, a := range albums {
		folder := a.folder
		if folder == "" && a.track != "" {
			folder = filepath.Dir(a.track)
		}
		picture := CoverInFolder(folder)
		if picture == "" && a.track != "" && ffmpeg != "" {
			out := filepath.Join(imageDir, "covers", a.id+".jpg")
			if err := extractEmbeddedCover(ffmpeg, a.track, out); err == nil {
				picture = out
			}
		}
		if picture == "" {
			db.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, 'cover:none', ?)
				ON CONFLICT DO NOTHING`, a.id, time.Now().UTC().Format("2006-01-02"))
			continue
		}
		sum := sha256.Sum256([]byte(picture + time.Now().String()))
		if _, err := db.Exec(`
			INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?, 'Primary', 0, ?, ?)
			ON CONFLICT(item_id, kind, idx) DO UPDATE SET path = excluded.path, tag = excluded.tag`,
			a.id, picture, hex.EncodeToString(sum[:8])); err != nil {
			log.Info("covers: could not record", "album", a.id, "error", err)
			continue
		}
		made++
	}
	if made > 0 {
		log.Info("covers: album covers found", "count", made)
	}
	return made, nil
}

// PendingMusicCovers says whether any album is still waiting for a cover.
func PendingMusicCovers(db *sql.DB) bool {
	var n int
	db.QueryRow(`SELECT count(*) FROM item a WHERE a.type = 'MusicAlbum'
		AND NOT EXISTS (SELECT 1 FROM image g WHERE g.item_id = a.id AND g.kind = 'Primary')
		AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = a.id AND v.kind = 'cover:none')
		LIMIT 1`).Scan(&n)
	return n > 0
}

// CoverInFolder is the picture an album's folder names as its cover, or "".
func CoverInFolder(folder string) string {
	if folder == "" {
		return ""
	}
	entries, err := os.ReadDir(folder)
	if err != nil {
		return ""
	}
	var images []string
	for _, e := range entries {
		ext := strings.ToLower(filepath.Ext(e.Name()))
		if e.IsDir() || (ext != ".jpg" && ext != ".jpeg" && ext != ".png") || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		stem := strings.ToLower(strings.TrimSuffix(e.Name(), filepath.Ext(e.Name())))
		for _, name := range coverNames {
			if stem == name {
				return filepath.Join(folder, e.Name())
			}
		}
		images = append(images, filepath.Join(folder, e.Name()))
	}
	// One picture and nothing else to choose between: that is the cover.
	if len(images) == 1 {
		return images[0]
	}
	return ""
}

// extractEmbeddedCover writes a track's attached picture as a JPEG.
func extractEmbeddedCover(ffmpeg, track, out string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	os.Remove(out)
	command := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-y", "-i", track,
		"-map", "0:v:0", "-frames:v", "1", "-vf", "scale='min(800,iw)':-2", "-q:v", "3", out)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg: %w: %s", err, strings.TrimSpace(string(output)))
	}
	if info, err := os.Stat(out); err != nil || info.Size() == 0 {
		return fmt.Errorf("no picture in %s", filepath.Base(track))
	}
	return nil
}
