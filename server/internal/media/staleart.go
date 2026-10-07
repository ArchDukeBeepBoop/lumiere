package media

import (
	"database/sql"
	"os"
)

// bare is a file needing a picture: which item, which file, how long.
type bare struct {
	id, path string
	ticks    int64
}

// staleArtwork lists files whose picture is a path that no longer resolves,
// and clears the rows naming it so the frame pass can replace them.
//
// The case is a file moved between folders. Its row keeps the pictures it
// had — that is the point of following a move — but a frame taken from the
// old path, or a still Jellyfin wrote into a metadata tree since tidied, can
// be gone from disk while the row still names it. The client asks for the
// image, the server has nothing to serve, and the tile is blank with a
// database that says it should not be.
//
// Every row is examined, not the newest few hundred. The first version
// capped the candidate scan by date to keep it cheap, and the blanks people
// actually see are old: a clip added in February whose frame was taken at a
// folder it has since left is exactly the row a recency cap never reaches.
// A stat is microseconds, so the whole table costs a fraction of a second
// once per pass.
func staleArtwork(db *sql.DB, limit int) ([]bare, error) {
	// Only the Primary picture: it is the one a tile draws, and a missing
	// backdrop beside a good poster is not a blank tile. Frames of our own
	// count too. They were skipped on the reasoning that a missing frame
	// means a missing file — but 247 frames went missing here while all 586
	// of their videos were still on disk, and every one was a tile that
	// Home drew from the app's cache and a See All page, asking for another
	// size, drew blank. The video is checked below instead.
	rows, err := db.Query(`
		SELECT i.id, i.path, COALESCE(i.runtime_ticks, 0), g.path
		FROM item i
		JOIN image g ON g.item_id = i.id AND g.kind = 'Primary' AND g.idx = 0
		WHERE i.is_folder = 0 AND i.path IS NOT NULL AND i.path <> ''
		  AND i.type IN ('Video', 'Movie', 'Episode')
		ORDER BY i.date_created DESC`)
	if err != nil {
		return nil, err
	}

	// Read to the end before anything is written: a DELETE issued while this
	// cursor is open takes a write lock the read still holds, and SQLite
	// answers SQLITE_BUSY rather than waiting.
	var found []bare
	for rows.Next() {
		var f bare
		var picture string
		if err := rows.Scan(&f.id, &f.path, &f.ticks, &picture); err != nil {
			rows.Close()
			return nil, err
		}
		if _, err := os.Stat(picture); err == nil {
			continue
		}
		// A frame needs its video to be retaken from; a video that is gone
		// is reconcile's business rather than this pass's.
		if _, err := os.Stat(f.path); err != nil {
			continue
		}
		found = append(found, f)
		if len(found) >= limit {
			break
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	for _, f := range found {
		if err := clearMissingArtwork(db, f.id); err != nil {
			return nil, err
		}
	}
	return found, nil
}

// clearMissingArtwork drops an item's image rows whose files are gone, and
// only those: a backdrop that survived is worth keeping, and the detail page
// still draws it.
func clearMissingArtwork(db *sql.DB, itemID string) error {
	rows, err := db.Query(`SELECT kind, idx, path FROM image WHERE item_id = ?`, itemID)
	if err != nil {
		return err
	}
	type key struct {
		kind string
		idx  int
	}
	var gone []key
	for rows.Next() {
		var k key
		var path string
		if err := rows.Scan(&k.kind, &k.idx, &path); err != nil {
			rows.Close()
			return err
		}
		if _, err := os.Stat(path); err != nil {
			gone = append(gone, k)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, k := range gone {
		if _, err := db.Exec(
			`DELETE FROM image WHERE item_id = ? AND kind = ? AND idx = ?`, itemID, k.kind, k.idx,
		); err != nil {
			return err
		}
	}
	return nil
}
