package store

// Pictures for folders, and for the shows and seasons of folder libraries.
//
// A folder of home videos has no artwork of its own, and neither does a show
// or season that the scan made from folder names in a library like My Videos
// or 3D: no provider knows them. Their videos each have a frame, but the tile
// for the folder above them stood blank — 1,130 such tiles, 101 of them in 3D
// alone. Each borrows the picture of the first thing in it that has one
// (nested folders pass a picture up level by level). A borrowed picture is
// tagged "inh-", is dropped when its source goes, and never replaces one that
// was set: only containers with no picture at all borrow.
//
// Shows and seasons in film and TV libraries are left alone. They have
// posters, or the app shows the show's poster in place of a season's, and a
// frame from an episode would be a worse picture than either.

const inheritedTag = "inh-"

// InheritContainerArt gives pictureless containers their first child's
// picture; returns how many it gave.
func (s *Store) InheritContainerArt() (int, error) {
	// A source that has gone takes its borrowed copies with it.
	if _, err := s.DB.Exec(`DELETE FROM image WHERE tag LIKE 'inh-%' AND path NOT IN
		(SELECT path FROM image WHERE tag NOT LIKE 'inh-%')`); err != nil {
		return 0, err
	}
	total := 0
	// One level per pass: a folder of folders gets its picture once its
	// first child has one.
	for pass := 0; pass < 8; pass++ {
		res, err := s.DB.Exec(`
			INSERT OR IGNORE INTO image (item_id, kind, idx, path, tag)
			SELECT p.id, 'Primary', 0, m.path, '` + inheritedTag + `' || m.tag
			FROM item p
			JOIN image m ON m.kind = 'Primary' AND m.idx = 0 AND m.item_id = (
				SELECT c.id FROM item c JOIN image cm ON cm.item_id = c.id AND cm.kind = 'Primary' AND cm.idx = 0
				WHERE c.parent_id = p.id AND c.extra_type IS NULL
				ORDER BY COALESCE(c.sort_name, c.name), c.id LIMIT 1)
			WHERE NOT EXISTS (SELECT 1 FROM image x WHERE x.item_id = p.id AND x.kind = 'Primary')
			  AND (p.type = 'Folder' OR (p.type IN ('Series', 'Season') AND EXISTS (
				SELECT 1 FROM library_folder lf JOIN item v ON v.id = lf.view_id
				WHERE lf.folder_id = p.library_id
				  AND COALESCE(v.collection_type, '') IN ('', 'homevideos', 'mixed'))))`)
		if err != nil {
			return total, err
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			break
		}
		total += int(n)
	}
	return total, nil
}
