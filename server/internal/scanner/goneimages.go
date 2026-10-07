package scanner

import (
	"database/sql"
	"log/slog"
	"os"
)

// dropGoneImages removes image rows whose files no longer exist.
//
// A row naming a missing file is worse than no row: the server answers 404,
// the tile is blank, and nothing refills it, because every pass that fetches
// or takes a picture skips items that already have one. The cache pruner
// deleted 328 such originals before it learnt to leave them alone. With the
// row gone the item simply has no picture, which the frame pass and the
// artwork fetch both know how to fix.
func dropGoneImages(db *sql.DB, log *slog.Logger) (int, error) {
	rows, err := db.Query(`SELECT item_id, kind, idx, path FROM image`)
	if err != nil {
		return 0, err
	}
	type key struct {
		item, kind string
		idx        int
	}
	var gone []key
	for rows.Next() {
		var k key
		var path string
		if rows.Scan(&k.item, &k.kind, &k.idx, &path) != nil {
			continue
		}
		if _, err := os.Stat(path); os.IsNotExist(err) {
			gone = append(gone, k)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil || len(gone) == 0 {
		return 0, err
	}
	// A whole volume that is not mounted is not a set of missing pictures:
	// if more than a tenth are gone, something is unplugged, and nothing is
	// dropped.
	var total int
	db.QueryRow(`SELECT count(*) FROM image`).Scan(&total)
	if len(gone)*10 > total {
		log.Warn("repair: too many pictures missing to be real; is a drive unplugged?", "missing", len(gone), "of", total)
		return 0, nil
	}
	tx, err := db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	for _, k := range gone {
		if _, err := tx.Exec(`DELETE FROM image WHERE item_id = ? AND kind = ? AND idx = ?`, k.item, k.kind, k.idx); err != nil {
			return 0, err
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	log.Info("repair: dropped pictures whose files are gone", "count", len(gone))
	return len(gone), nil
}
