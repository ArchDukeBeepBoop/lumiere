package media

import (
	"database/sql"
	"fmt"
	"os"
)

// Frames that no longer match their video, and videos that cannot give one.
//
// A frame was taken once and trusted for good. A file edited in place — a
// re-encode, a fixed release swapped in under the same name — kept the old
// picture forever, and nothing noticed. And a file ffmpeg cannot read (one
// here is a download that stopped at its first byte) was tried again on every
// pass, logging the same failure thirty-five times.
//
// Both are answered by one fingerprint: the video's size and modification
// time, recorded beside the frame when it is taken. A different fingerprint
// is a different file, so the frame is taken again. A move or a rename keeps
// both, so a moved file keeps its frame — and a failure is remembered against
// the fingerprint, so a broken file is left alone until it changes.

// videoFingerprint is "size:mtime", or "" when the file cannot be read.
func videoFingerprint(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return ""
	}
	return fmt.Sprintf("%d:%d", info.Size(), info.ModTime().Unix())
}

// changedFrames lists the files whose frame was taken from a different
// version of them. Frames recorded before fingerprints existed are adopted
// as they are — there is no telling what they were taken from.
func changedFrames(db *sql.DB, limit int) ([]bare, error) {
	rows, err := db.Query(`
		SELECT i.id, i.path, COALESCE(i.runtime_ticks, 0),
		       COALESCE((SELECT v.value FROM item_value v WHERE v.item_id = i.id AND v.kind = 'frame:source'), '')
		FROM item i JOIN image g ON g.item_id = i.id AND g.kind = 'Primary' AND g.idx = 0
		WHERE i.is_folder = 0 AND COALESCE(i.path, '') <> '' AND (
			g.path LIKE '%/frames/%'
			-- A picture Jellyfin took of an unscraped video is a frame as much as
			-- ours is, and goes stale the same way when the file is replaced.
			-- Scraped stills and posters are left alone: they describe the title,
			-- not the bytes.
			OR (i.type IN ('Video', 'Episode') AND NOT EXISTS (
				SELECT 1 FROM item_value p WHERE p.item_id = i.id AND (p.kind = 'episode:enriched'
				     OR (p.kind LIKE 'provider:%' AND p.kind <> 'provider:none')))))`)
	if err != nil {
		return nil, err
	}
	type seen struct {
		f      bare
		stored string
	}
	var all []seen
	for rows.Next() {
		var s seen
		if rows.Scan(&s.f.id, &s.f.path, &s.f.ticks, &s.stored) == nil {
			all = append(all, s)
		}
	}
	rows.Close()
	var changed []bare
	for _, s := range all {
		now := videoFingerprint(s.f.path)
		switch {
		case now == "":
			// Unreachable — an unmounted drive, most often. Not a change.
		case s.stored == "":
			setFrameValue(db, s.f.id, "frame:source", now)
		case s.stored != now && len(changed) < limit:
			changed = append(changed, s.f)
		}
	}
	return changed, nil
}

// failedBefore says whether this exact version of the file already failed
// with the extraction as it is now. The version tag means a better extractor
// retries what an older one gave up on.
func failedBefore(db *sql.DB, id, fingerprint string) bool {
	var v string
	db.QueryRow(`SELECT value FROM item_value WHERE item_id = ? AND kind = 'frame:failed'`, id).Scan(&v)
	return v != "" && v == failureMark(fingerprint)
}

// failureMark is what a failure is remembered as. Bump the version when
// extraction learns to read files it could not before.
func failureMark(fingerprint string) string { return "v2:" + fingerprint }

func setFrameValue(db *sql.DB, id, kind, value string) {
	db.Exec(`DELETE FROM item_value WHERE item_id = ? AND kind = ?`, id, kind)
	if value != "" {
		db.Exec(`INSERT INTO item_value (item_id, kind, value) VALUES (?, ?, ?)`, id, kind, value)
	}
}
