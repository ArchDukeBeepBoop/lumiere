package store

import "testing"

func TestAniListRecheckPutsBackOnlyTheUnmatchedOnce(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder, library_id) VALUES
			('kabuki', 'Series', 'Kabukimonogatari (2013)', 1, 'anime'),
			('nise', 'Series', 'Nisemonogatari', 1, 'anime'),
			('other', 'Series', 'Elsewhere', 1, 'films')`,
		`INSERT INTO item_value (item_id, kind, value) VALUES
			('kabuki', 'anilist:checked', '1'), ('nise', 'anilist:checked', '1'),
			('nise', 'provider:AniList', '11597'), ('other', 'anilist:checked', '1')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if n := s.AniListRecheck([]string{"anime"}); n != 1 {
		t.Fatalf("put back %d, want only Kabukimonogatari", n)
	}
	if got := s.AniListUnchecked([]string{"anime"}, 10); len(got) != 1 || got[0].ID != "kabuki" {
		t.Fatalf("unchecked: %+v", got)
	}
	s.SetAniListMatch("kabuki", 0, "")
	if n := s.AniListRecheck([]string{"anime"}); n != 0 {
		t.Fatal("the recheck is done once")
	}
}

func TestAniListArtIsOnUnlessTurnedOff(t *testing.T) {
	s := testStore(t)
	if !s.AniListArtOn() {
		t.Fatal("on by default")
	}
	s.SetMeta(MetaAniListArt, "off")
	if s.AniListArtOn() {
		t.Fatal("off when turned off")
	}
}
