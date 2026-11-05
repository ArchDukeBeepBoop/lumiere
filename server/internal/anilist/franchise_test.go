package anilist

import (
	"reflect"
	"testing"
)

func TestComponentsFollowStoryNotCameos(t *testing.T) {
	nodes := map[int]Node{
		1: {ID: 1, Romaji: "Fate/stay night", Year: 2006, Format: "TV", Relations: []Edge{{ID: 2, Kind: "ALTERNATIVE", Anime: true}, {ID: 9, Kind: "SOURCE", Anime: false}}},
		2: {ID: 2, Romaji: "Fate/stay night: Unlimited Blade Works", Year: 2014, Format: "TV", Relations: []Edge{{ID: 3, Kind: "PREQUEL", Anime: true}}},
		3: {ID: 3, Romaji: "Fate/Zero", Year: 2011, Format: "TV"},
		4: {ID: 4, Romaji: "Lupin III", Year: 1971, Format: "TV", Relations: []Edge{{ID: 5, Kind: "CHARACTER", Anime: true}}},
		5: {ID: 5, Romaji: "Detective Conan", Year: 1996, Format: "TV"},
	}
	got := Components(nodes)
	want := [][]int{{1, 2, 3}, {4}, {5}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
	if name := Name(nodes, got[0]); name != "Fate" {
		t.Fatalf("named %q", name)
	}
}

func TestBaseTitleDropsSeasons(t *testing.T) {
	for in, want := range map[string]string{
		"Attack on Titan Season 2":       "Attack on Titan",
		"Mob Psycho 100 III":             "Mob Psycho 100 III",
		"Haikyu!! 2nd Season":            "Haikyu!!",
		"Demon Slayer: The Movie":        "Demon Slayer",
		"Re:ZERO -Starting Life- Part 2": "Re:ZERO -Starting Life",
	} {
		if got := BaseTitle(in); got != want {
			t.Errorf("%q → %q, want %q", in, got, want)
		}
	}
}

func TestMatchIsStrict(t *testing.T) {
	results := []Node{
		{ID: 1, Romaji: "Shingeki no Kyojin", English: "Attack on Titan", Year: 2013, Format: "TV"},
		{ID: 2, Romaji: "Shingeki no Kyojin Movie", Year: 2015, Format: "MOVIE"},
	}
	if n, ok := Match("Attack on Titan", "", 2013, false, results); !ok || n.ID != 1 {
		t.Fatal("the English title should match the series")
	}
	if _, ok := Match("Attack on Titan", "", 2013, true, results); ok {
		t.Fatal("a film must not match a series")
	}
	if _, ok := Match("Attack on Titan", "", 2005, false, results); ok {
		t.Fatal("eight years out is a different title")
	}
	if _, ok := Match("Titan", "", 0, false, results); ok {
		t.Fatal("a near name is not a match")
	}
}

func TestSeasonsFollowSequelsOverFilms(t *testing.T) {
	nodes := map[int]Node{
		1: {ID: 1, Format: "TV", Year: 2013, Relations: []Edge{{ID: 2, Kind: "SEQUEL", Anime: true}, {ID: 5, Kind: "SIDE_STORY", Anime: true}}},
		2: {ID: 2, Format: "MOVIE", Year: 2015, Relations: []Edge{{ID: 3, Kind: "SEQUEL", Anime: true}}},
		3: {ID: 3, Format: "TV", Year: 2017, Relations: []Edge{{ID: 4, Kind: "SEQUEL", Anime: true}}},
		4: {ID: 4, Format: "TV", Year: 2019},
		5: {ID: 5, Format: "OVA", Year: 2014},
	}
	if got := Seasons(nodes, 1); !reflect.DeepEqual(got, []int{1, 3, 4}) {
		t.Fatalf("seasons %v", got)
	}
	if got := Specials(nodes, []int{1, 3, 4}); got != 5 {
		t.Fatalf("specials %d", got)
	}
	if got := Chronology(nodes, []int{4, 1, 5, 3, 2}); !reflect.DeepEqual(got, []int{1, 5, 2, 3, 4}) {
		t.Fatalf("chronology %v", got)
	}
}

func TestNameIsWhatMostEntriesShare(t *testing.T) {
	nodes := map[int]Node{
		1: {ID: 1, English: "Lupin III: Pilot Film", Year: 1969, Format: "MOVIE"},
		2: {ID: 2, English: "Lupin III", Year: 1971, Format: "TV"},
		3: {ID: 3, English: "Lupin III: Part II", Year: 1977, Format: "TV"},
		4: {ID: 4, English: "Lupin III: The Castle of Cagliostro", Year: 1979, Format: "MOVIE"},
		5: {ID: 5, English: "", Romaji: "Lupin Sansei", Year: 1980, Format: "MOVIE"},
	}
	if got := Name(nodes, []int{1, 2, 3, 4, 5}); got != "Lupin III" {
		t.Fatalf("named %q", got)
	}
	mono := map[int]Node{
		1: {ID: 1, English: "Bakemonogatari", Year: 2009, Format: "TV"},
		2: {ID: 2, English: "Nisemonogatari", Year: 2012, Format: "TV"},
	}
	if got := Name(mono, []int{1, 2}); got != "Bakemonogatari" {
		t.Fatalf("no shared words: the first show, got %q", got)
	}
}

func TestNameAvoidsDanglingWords(t *testing.T) {
	geass := map[int]Node{
		1: {ID: 1, English: "Code Geass: Lelouch of the Rebellion", Year: 2006, Format: "TV"},
		2: {ID: 2, English: "Code Geass: Lelouch of the Rebellion R2", Year: 2008, Format: "TV"},
		3: {ID: 3, English: "Code Geass: Lelouch of the Re;surrection", Year: 2019, Format: "MOVIE"},
	}
	if got := Name(geass, []int{1, 2, 3}); got != "Code Geass" {
		t.Fatalf("named %q", got)
	}
	gundam := map[int]Node{
		1: {ID: 1, English: "Mobile Suit Gundam", Year: 1979, Format: "TV"},
		2: {ID: 2, English: "Mobile Fighter G Gundam", Year: 1994, Format: "TV"},
		3: {ID: 3, English: "Mobile Suit Zeta Gundam", Year: 1985, Format: "TV"},
	}
	if got := Name(gundam, []int{1, 2, 3}); got != "Mobile Suit Gundam" {
		t.Fatalf("named %q", got)
	}
}
