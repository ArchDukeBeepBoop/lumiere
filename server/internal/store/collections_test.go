package store

import "testing"

func TestNewCollectionsLiveWithTheOthers(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, parent_id, library_id) VALUES ('old', 'BoxSet', 'Old', 1, 'home', 'lib')`)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('stray', 'BoxSet', 'Stray', 1)`)

	id, err := s.CreateContainer("BoxSet", "New", []string{"a", "b"})
	if err != nil {
		t.Fatal(err)
	}
	var parent string
	s.DB.QueryRow(`SELECT COALESCE(parent_id, '') FROM item WHERE id = ?`, id).Scan(&parent)
	if parent != "home" {
		t.Fatalf("new collection filed under %q, want home", parent)
	}
	if n, _ := s.HomeStrayCollections(); n != 1 {
		t.Fatalf("homed %d strays, want 1", n)
	}
	if added, _ := s.AddMissingLinks(id, []string{"a", "c"}); added != 1 {
		t.Fatalf("added %d, want only the missing one", added)
	}
}

func TestMarkingACollectionWatchedMarksItsMembers(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('c', 'BoxSet', 'C', 1), ('f', 'Movie', 'F', 0), ('g', 'Movie', 'G', 0)`)
	s.AddLinks("c", []string{"f", "g"})
	if err := s.SetPlayed("c", true); err != nil {
		t.Fatal(err)
	}
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM user_data WHERE item_id IN ('f','g') AND played = 1`).Scan(&n)
	if n != 2 {
		t.Fatalf("%d members marked, want 2", n)
	}
}

func TestSeriesNextOffersTheFilmAfterTheLastWatched(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, premiere_date) VALUES
		('c', 'BoxSet', 'Alien', 1, NULL), ('a1', 'Movie', 'Alien', 0, '1979-05-25'),
		('a2', 'Movie', 'Aliens', 0, '1986-07-18'), ('a3', 'Movie', 'Alien 3', 0, '1992-05-22'),
		('u', 'BoxSet', 'Untouched', 1, NULL), ('x', 'Movie', 'X', 0, '2000-01-01')`)
	s.AddLinks("c", []string{"a3", "a1", "a2"})
	s.AddLinks("u", []string{"x"})
	s.SetPlayed("a1", true)
	ids, err := s.SeriesNext(10)
	if err != nil || len(ids) != 1 || ids[0] != "a2" {
		t.Fatalf("got %v (%v), want [a2]", ids, err)
	}
	s.SetPlayed("a2", true)
	if ids, _ = s.SeriesNext(10); len(ids) != 1 || ids[0] != "a3" {
		t.Fatalf("got %v, want [a3]", ids)
	}
}

func TestTheNextFilmInItsCollection(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, premiere_date) VALUES
		('c', 'BoxSet', 'Alien Collection', 1, NULL), ('a1', 'Movie', 'Alien', 0, '1979-05-25'),
		('a2', 'Movie', 'Aliens', 0, '1986-07-18')`)
	s.AddLinks("c", []string{"a2", "a1"})
	if next, name := s.NextInCollection("a1"); next != "a2" || name != "Alien Collection" {
		t.Fatalf("got %q %q", next, name)
	}
	if next, _ := s.NextInCollection("a2"); next != "" {
		t.Fatalf("the last film has no next, got %q", next)
	}
}
