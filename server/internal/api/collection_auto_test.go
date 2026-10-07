package api

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

func TestAutoCollectionsRoomByRoomAdoptingAndLeavingOut3D(t *testing.T) {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "data"))
	if err != nil {
		t.Fatal(err)
	}
	// Three libraries: films, a private one, and 3D.
	for _, l := range [][3]string{{"vFilms", "fFilms", "Movies"}, {"vPriv", "fPriv", "Hidden"}, {"v3d", "f3d", "3D"}} {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES (?, 'CollectionFolder', ?, 1)`, l[0], l[2])
		s.DB.Exec(`INSERT INTO library_folder (view_id, folder_id) VALUES (?, ?)`, l[0], l[1])
	}
	s.SetMeta(metaPrivateLibraries, "vPriv")
	film := func(id, name, lib, series string) {
		s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, library_id) VALUES (?, 'Movie', ?, 0, ?)`, id, name, lib)
		s.SetItemValue(id, "provider:TmdbCollection", series)
	}
	film("a1", "Alien", "fFilms", "8091")
	film("a2", "Aliens", "fFilms", "8091")
	film("h1", "Hidden One", "fPriv", "500")
	film("h2", "Hidden Two", "fPriv", "500")
	film("d1", "Deep 3D", "f3d", "600")
	film("d2", "Deeper 3D", "f3d", "600")
	film("s1", "Solo", "fFilms", "700")
	// Predator: a collection made by hand already holds both films.
	film("p1", "Predator", "fFilms", "399")
	film("p2", "Predators", "fFilms", "399")
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder) VALUES ('hand', 'BoxSet', 'My Predators', 1)`)
	s.AddLinks("hand", []string{"p1", "p2"})

	h := CollectionSuggestHandler{Store: s, DataDir: dir, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	made, adopted := h.AutoCollections(context.Background())
	if made != 2 || adopted != 1 {
		t.Fatalf("made %d, adopted %d — want Alien and the private pair made, Predator adopted", made, adopted)
	}
	var boxsets int
	s.DB.QueryRow(`SELECT count(*) FROM item WHERE type = 'BoxSet'`).Scan(&boxsets)
	if boxsets != 3 {
		t.Errorf("%d collections; 3D and a lone film make none, Predator is not duplicated", boxsets)
	}
	var privLib string
	s.DB.QueryRow(`SELECT COALESCE(b.library_id, '') FROM item b JOIN link l ON l.parent_id = b.id
		WHERE l.child_id = 'h1' AND b.type = 'BoxSet'`).Scan(&privLib)
	if privLib != "fPriv" {
		t.Errorf("the private pair's collection lives in its library, got %q", privLib)
	}
	var alienLib string
	s.DB.QueryRow(`SELECT COALESCE(b.library_id, '') FROM item b JOIN link l ON l.parent_id = b.id
		WHERE l.child_id = 'a1' AND b.type = 'BoxSet'`).Scan(&alienLib)
	if alienLib == "fPriv" {
		t.Error("a collection outside the room must not be filed in the private library")
	}
	if s.ItemValue("hand", "tmdb_collection") != "399" {
		t.Error("the adopted collection learns its series")
	}
	// Again: nothing new.
	if made, adopted := h.AutoCollections(context.Background()); made != 0 || adopted != 0 {
		t.Errorf("a second pass made %d and adopted %d", made, adopted)
	}
}
