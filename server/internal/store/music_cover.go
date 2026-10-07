package store

import (
	"database/sql"
	"errors"
)

// MusicCoverFor is the picture to show for a track or album that has none of
// its own: a track borrows its album's cover, an album the first cover among
// its tracks. 75 tracks and 60 albums here drew blank tiles and a blank
// player without it, while the cover was one level away.
func (s *Store) MusicCoverFor(itemID string) (ImageRef, error) {
	var ref ImageRef
	var width sql.NullInt64
	err := s.DB.QueryRow(`
		SELECT g.path, g.tag, g.width FROM item i
		JOIN image g ON g.kind = 'Primary' AND g.idx = 0 AND (
			(i.type = 'Audio' AND g.item_id = i.parent_id)
			OR (i.type = 'MusicAlbum' AND g.item_id IN
			    (SELECT t.id FROM item t WHERE t.parent_id = i.id AND t.type = 'Audio')))
		WHERE i.id = ? LIMIT 1`, itemID).Scan(&ref.Path, &ref.Tag, &width)
	if errors.Is(err, sql.ErrNoRows) {
		return ImageRef{}, ErrNoImage
	}
	ref.Width = int(width.Int64)
	return ref, err
}
