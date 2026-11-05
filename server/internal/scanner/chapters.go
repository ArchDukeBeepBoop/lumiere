package scanner

import (
	"context"
	"database/sql"
	"log/slog"
	"os"
	"os/exec"
	"sync"
	"time"

	"lumiere-server/internal/store"
)

// A file's own chapters, read from the file.
//
// Chapters came only from the Jellyfin import, and went with the database on
// 25 October: none were left, so no file had the "Opening" and "Ending"
// chapters Skip Intro and Skip Credits are made from (see
// store.ChapterSegments), and the skip offers disappeared. The scan now reads
// them with everything else, and this reads them once for the files already
// here.

// chaptersRead marks a file whose chapters have been read, any or none.
const chaptersRead = "chapters:read"

type execer interface {
	Exec(query string, args ...any) (sql.Result, error)
}

// writeChapters replaces a file's chapters with these.
func writeChapters(db execer, itemID string, chapters []ProbeChapter) {
	db.Exec(`DELETE FROM chapter WHERE item_id = ?`, itemID)
	for i, c := range chapters {
		db.Exec(`INSERT OR REPLACE INTO chapter (item_id, idx, start_ticks, name) VALUES (?, ?, ?, ?)`,
			itemID, i, int64(c.StartSeconds*10_000_000), nullString(c.Name))
	}
	db.Exec(`INSERT OR IGNORE INTO item_value (item_id, kind, value) VALUES (?, ?, '1')`, itemID, chaptersRead)
}

// probeChapters reads only the chapters, which is quick.
func probeChapters(tool, path string) ([]ProbeChapter, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, tool, "-v", "quiet", "-print_format", "json", "-show_chapters", path).Output()
	if err != nil {
		return nil, err
	}
	p, err := parseProbe(out)
	return p.Chapters, err
}

// ReadMissingChapters reads the chapters of every video not yet read —
// episodes first, newest first — four at a time, in the background. A file
// that cannot be read (its drive unplugged) is left for the next start.
func ReadMissingChapters(db *store.Store, log *slog.Logger) {
	tool := FindFFprobe()
	if tool == "" {
		return
	}
	rows, err := db.DB.Query(`SELECT id, path FROM item i
		WHERE type IN ('Episode', 'Movie', 'Video') AND is_folder = 0 AND path IS NOT NULL AND path <> ''
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id AND v.kind = ?)
		ORDER BY type = 'Episode' DESC, date_created DESC`, chaptersRead)
	if err != nil {
		return
	}
	type file struct{ id, path string }
	var files []file
	for rows.Next() {
		var f file
		rows.Scan(&f.id, &f.path)
		files = append(files, f)
	}
	rows.Close()
	if len(files) == 0 {
		return
	}
	log.Info("chapters: reading them from the files", "files", len(files))
	work := make(chan file)
	var mu sync.Mutex
	var read, named int
	var wg sync.WaitGroup
	for w := 0; w < 4; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for f := range work {
				if _, err := os.Stat(f.path); err != nil {
					continue
				}
				chapters, err := probeChapters(tool, f.path)
				if err != nil {
					continue
				}
				mu.Lock()
				writeChapters(db.DB, f.id, chapters)
				read++
				if len(chapters) > 0 {
					named++
				}
				mu.Unlock()
			}
		}()
	}
	for _, f := range files {
		work <- f
	}
	close(work)
	wg.Wait()
	log.Info("chapters: read", "files", read, "with chapters", named)
}
