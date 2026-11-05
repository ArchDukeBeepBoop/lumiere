package store

import "testing"

func TestFavoritePeopleAreTheStarredOnesWithTheirPhotos(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO person (item_id, person_id, name, role, type) VALUES
			('f1', 'kana', 'Kana Hanazawa', 'Nadeko', 'Actor'), ('f2', 'kana', 'Kana Hanazawa', 'Mayuri', 'Actor'),
			('f1', 'shaft', 'Akiyuki Shinbo', '', 'Director'), ('f1', 'other', 'Someone Else', 'x', 'Actor')`,
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES ('kana', 'Primary', 0, '/p.jpg', 'tk')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	s.SetFavorite("kana", true)
	s.SetFavorite("shaft", true)
	s.SetFavorite("other", true)
	s.SetFavorite("other", false)
	got, err := s.FavoritePeople()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].ID != "kana" || got[0].Credits != 2 || got[0].Tag != "tk" || got[1].ID != "shaft" || got[1].Tag != "" {
		t.Fatalf("favourites: %+v", got)
	}
}
