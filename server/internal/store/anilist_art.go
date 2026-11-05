package store

import (
	"strings"
	"time"
)

// AniList's pictures, and second chances for titles it did not find.

// MetaAniListArt is "off" when franchise collections keep the four-poster
// mosaic; otherwise they wear their first entry's key art from AniList, and
// shows with no backdrop or poster borrow their entry's.
const MetaAniListArt = "anilist_art"

// MetaAniListRecheck records when titles AniList did not find were last put
// back to be looked up again — once per change to matching: v2 when it
// learned a folder's year and a title's original name, v3 a folder of films
// under the series' bare name.
const MetaAniListRecheck = "anilist_recheck_v3"

// AniListArtOn says whether AniList's pictures are used.
func (s *Store) AniListArtOn() bool {
	v, _ := s.Meta(MetaAniListArt)
	return v != "off"
}

// AniListRecheck puts the unmatched titles in these folders back in the
// queue, once; returns how many.
func (s *Store) AniListRecheck(folders []string) int {
	if done, _ := s.Meta(MetaAniListRecheck); done != "" || len(folders) == 0 {
		return 0
	}
	args := []any{}
	for _, f := range folders {
		args = append(args, f)
	}
	res, err := s.DB.Exec(`DELETE FROM item_value WHERE kind = 'anilist:checked' AND item_id IN (
		SELECT id FROM item i WHERE library_id IN (?`+strings.Repeat(",?", len(folders)-1)+`)
		  AND NOT EXISTS (SELECT 1 FROM item_value v WHERE v.item_id = i.id AND v.kind = 'provider:AniList'))`, args...)
	if err != nil {
		return 0
	}
	s.SetMeta(MetaAniListRecheck, time.Now().UTC().Format(time.RFC3339))
	n, _ := res.RowsAffected()
	return int(n)
}

// ImageTags is an item's pictures, kind → tag, first of each kind.
func (s *Store) ImageTags(itemID string) map[string]string {
	out := map[string]string{}
	rows, err := s.DB.Query(`SELECT kind, tag FROM image WHERE item_id = ? AND idx = 0`, itemID)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var kind, tag string
		rows.Scan(&kind, &tag)
		out[kind] = tag
	}
	return out
}
