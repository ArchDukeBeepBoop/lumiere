package store

import "testing"

func TestNextInAFranchiseFollowsItsOrderAndShows(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, sort_name, is_folder, production_year) VALUES
			('mono', 'BoxSet', 'Monogatari', 'Monogatari', 1, NULL),
			('vamp', 'BoxSet', 'Vampires', 'Vampires', 1, NULL),
			('bake', 'Series', 'Monogatari', 'Monogatari', 1, 2009),
			('kizu', 'Series', 'Kizumonogatari', 'Kizumonogatari', 1, 2016),
			('nise', 'Series', 'Nisemonogatari', 'Nisemonogatari', 1, 2012),
			('dracula', 'Movie', 'Dracula', 'Dracula', 0, 1931)`,
		`INSERT INTO link (parent_id, child_id, position) VALUES
			('mono', 'bake', 0), ('mono', 'nise', 1), ('mono', 'kizu', 2),
			('vamp', 'kizu', 0), ('vamp', 'dracula', 1)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('mono', 'anilist:franchise', '5081:library')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	if next, name, id := s.NextInCollection("bake"); next != "nise" || name != "Monogatari" || id != "mono" {
		t.Fatalf("after Bakemonogatari: %q in %q", next, name)
	}
	if next, _, _ := s.NextInCollection("kizu"); next != "" {
		t.Fatalf("the franchise's last entry has none, even in a theme: %q", next)
	}
	if next, name, _ := s.NextInCollection("dracula"); next != "kizu" || name != "Vampires" {
		t.Fatalf("a theme orders by date, shows too: %q in %q", next, name)
	}
}
