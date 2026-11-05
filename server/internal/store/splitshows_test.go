package store

import (
	"io"
	"log/slog"
	"testing"
)

func TestSplitShowsFoldUnlessTheirEpisodesCollide(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, library_id, path, is_folder, date_created) VALUES
			('onii', 'Series', 'Big Brother', 'anime', '/A/Onii-chan', 1, '2026-07-01'),
			('onii-s1', 'Season', 'Season 1', 'anime', '/A/Onii-chan/Season 1', 1, '2026-07-01'),
			('new', 'Series', 'Big Brother', 'anime', '/A/Because I Dont', 1, '2026-10-31'),
			('new-s0', 'Season', 'Specials', 'anime', '/A/Because I Dont/Specials', 1, '2026-10-31'),
			('aris', 'Series', 'Aristocrat', 'anime', '/A/Aristocrat', 1, '2026-07-01'),
			('aris-s3', 'Season', 'Season 3', 'anime', '/A/Aristocrat/Season 3', 1, '2026-07-01'),
			('aris2', 'Series', 'Aristocrat', 'anime', '/A/Aristocrat New', 1, '2026-10-26'),
			('aris2-s3', 'Season', 'Season 3', 'anime', '/A/Aristocrat New/Season 3', 1, '2026-10-26'),
			('sou', 'Series', 'Kaze Yuugi', 'h', '/H/Kaze Yuugi', 1, '2026-07-01'),
			('sou-s1', 'Season', 'Season 1', 'h', '/H/Kaze Yuugi/Season 1', 1, '2026-07-01'),
			('sou2', 'Series', 'Kaze Yuugi', 'h', '/H/Kaze Yuugi 2', 1, '2026-07-02'),
			('sou2-s1', 'Season', 'Season 1', 'h', '/H/Kaze Yuugi 2/Season 1', 1, '2026-07-02'),
			('pair', 'BoxSet', 'Aristocrat', NULL, NULL, 1, '2026-10-27')`,
		`UPDATE item SET parent_id = 'onii', series_id = 'onii', index_number = 1 WHERE id = 'onii-s1'`,
		`UPDATE item SET parent_id = 'new', series_id = 'new', index_number = 0 WHERE id = 'new-s0'`,
		`UPDATE item SET parent_id = 'aris', series_id = 'aris', index_number = 3 WHERE id = 'aris-s3'`,
		`UPDATE item SET parent_id = 'aris2', series_id = 'aris2', index_number = 3 WHERE id = 'aris2-s3'`,
		`UPDATE item SET parent_id = 'sou', series_id = 'sou', index_number = 1 WHERE id = 'sou-s1'`,
		`UPDATE item SET parent_id = 'sou2', series_id = 'sou2', index_number = 1 WHERE id = 'sou2-s1'`,
		`INSERT INTO item (id, type, name, library_id, parent_id, series_id, season_id, parent_index_number, index_number, is_folder) VALUES
			('e1', 'Episode', 'One', 'anime', 'onii-s1', 'onii', 'onii-s1', 1, 1, 0),
			('sp1', 'Episode', 'Special', 'anime', 'new-s0', 'new', 'new-s0', 0, 1, 0),
			('a1', 'Episode', 'A1', 'anime', 'aris-s3', 'aris', 'aris-s3', 3, 1, 0),
			('a2', 'Episode', 'A2', 'anime', 'aris2-s3', 'aris2', 'aris2-s3', 3, 2, 0),
			('s1', 'Episode', 'S1', 'h', 'sou-s1', 'sou', 'sou-s1', 1, 1, 0),
			('s2', 'Episode', 'S2', 'h', 'sou2-s1', 'sou2', 'sou2-s1', 1, 1, 0)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES
			('onii', 'provider:Tmdb', '46170'), ('new', 'provider:Tmdb', '46170'),
			('aris', 'provider:Tmdb', '237150'), ('aris2', 'provider:Tmdb', '237150'),
			('sou', 'provider:Tmdb', '125617'), ('sou2', 'provider:Tmdb', '125617'),
			('pair', 'anilist:franchise', '1:library')`,
		`INSERT INTO link (parent_id, child_id, position) VALUES ('pair', 'aris', 0), ('pair', 'aris2', 1)`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if n := s.MergeSplitShows(slog.New(slog.NewTextHandler(io.Discard, nil))); n != 2 {
		t.Fatalf("folded %d, want the specials and the extra season", n)
	}
	field := func(id, col string) string {
		var v string
		s.DB.QueryRow(`SELECT COALESCE(`+col+`, '') FROM item WHERE id = ?`, id).Scan(&v)
		return v
	}
	if field("new-s0", "parent_id") != "onii" || field("sp1", "series_id") != "onii" || field("new", "id") != "" {
		t.Fatal("the specials season moves to the show already here, and the split show goes")
	}
	if field("a2", "parent_id") != "aris-s3" || field("aris2-s3", "id") != "" || field("aris2", "id") != "" {
		t.Fatal("a season the show already has takes the episodes; the empty copy goes")
	}
	if field("sou2", "id") == "" || field("s2", "series_id") != "sou2" {
		t.Fatal("colliding episodes keep the two apart")
	}
	if field("pair", "id") != "" {
		t.Fatal("the collection the split made, left with one member, goes")
	}
	var alias string
	s.DB.QueryRow(`SELECT value FROM item_value WHERE item_id = 'onii' AND kind = 'folder:alias'`).Scan(&alias)
	if alias != "/A/Because I Dont" {
		t.Fatalf("the folded folder is remembered: %q", alias)
	}
}
