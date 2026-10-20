package api

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestThemeCollectionsByRoomFollowTheLibraryAndSwitchOff(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range [][2]string{{"vMain", "fMain"}, {"vPriv", "fPriv"}} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'CollectionFolder', ?, 1)`, l[0], l[0])
		s.DB.Exec(`INSERT INTO library_folder (view_id, folder_id) VALUES (?, ?)`, l[0], l[1])
	}
	s.SetMeta(metaPrivateLibraries, "vPriv")
	title := func(id, lib, tag string) {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, library_id) VALUES (?, 'Movie', ?, 0, ?)`, id, id, lib)
		s.AddTags(id, []string{tag})
	}
	title("a", "fMain", "Time Loop")
	title("b", "fMain", "time loop")
	title("c", "fMain", "groundhog day")
	title("p1", "fPriv", "time loop") // one private title: too few for a shelf
	h := CollectionSuggestHandler{Store: s, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}

	made, _ := h.ThemeCollections(context.Background())
	rooms := s.LibraryRooms([]string{"vPriv"})
	id := s.ThemeCollectionFor("time-loops", false, rooms)
	if made != 1 || id == "" || s.ThemeCollectionFor("time-loops", true, rooms) != "" {
		t.Fatalf("made %d, main %q", made, id)
	}

	// A title leaves the library: the collection follows.
	s.DB.Exec(`DELETE FROM item_value WHERE item_id = 'c'`)
	title("d", "fMain", "time loop")
	h.ThemeCollections(context.Background())
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM link WHERE parent_id = ? AND child_id IN ('a','b','d')`, id).Scan(&n)
	var stale int
	s.DB.QueryRow(`SELECT count(*) FROM link WHERE parent_id = ? AND child_id = 'c'`, id).Scan(&stale)
	if n != 3 || stale != 0 {
		t.Fatalf("members %d, stale %d", n, stale)
	}

	// Switched off: gone.
	themes := s.Themes()
	for i := range themes {
		if themes[i].Slug == "time-loops" {
			themes[i].Enabled = false
		}
	}
	s.SaveThemes(themes)
	h.ThemeCollections(context.Background())
	if s.ThemeCollectionFor("time-loops", false, rooms) != "" {
		t.Fatal("still there after switching off")
	}
}

func TestAThemeCollectionIdentifiedAsASeriesIsPutBackAndGetsItsOwnArt(t *testing.T) {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "data"))
	if err != nil {
		t.Fatal(err)
	}
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('v', 'CollectionFolder', 'Films', 1)`)
	s.DB.Exec(`INSERT INTO library_folder (view_id, folder_id) VALUES ('v', 'f')`)
	for _, id := range []string{"a", "b", "c"} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, library_id) VALUES (?, 'Movie', ?, 0, 'f')`, id, id)
		s.AddTags(id, []string{"time loop"})
	}
	h := CollectionSuggestHandler{Store: s, DataDir: dir, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	h.ThemeCollections(context.Background())
	id := s.ThemeCollectionFor("time-loops", false, s.LibraryRooms(nil))
	if s.ItemValue(id, "art:theme") == "" {
		t.Fatal("no artwork designed")
	}
	// Identified by mistake.
	s.SetItemValue(id, "tmdb_collection", "210303")
	s.DB.Exec(`UPDATE item SET name = 'Rebuild of Evangelion Collection' WHERE id = ?`, id)
	h.ThemeCollections(context.Background())
	var name string
	s.DB.QueryRow(`SELECT name FROM item WHERE id = ?`, id).Scan(&name)
	if name != "Time Loops" || s.ItemValue(id, "tmdb_collection") != "" || s.ItemValue(id, "art:theme") == "" {
		t.Fatalf("not put back: %q", name)
	}
	if s.CollectionHolding([]string{"a", "b", "c"}) == id {
		t.Fatal("a theme collection was offered for adoption as a series")
	}
}
