package anilist

import "testing"

// The Monogatari series, as AniList has it: every entry is its own title,
// joined only by the ending they share.
func monogatari() (map[int]Node, []int) {
	nodes := map[int]Node{
		5081:   {ID: 5081, Romaji: "Bakemonogatari", English: "Bakemonogatari", Year: 2009, Format: "TV"},
		11597:  {ID: 11597, Romaji: "Nisemonogatari", English: "Nisemonogatari", Year: 2012, Format: "TV"},
		15689:  {ID: 15689, Romaji: "Nekomonogatari (Kuro)", English: "Nekomonogatari: Black", Year: 2012, Format: "TV"},
		17074:  {ID: 17074, Romaji: "Monogatari Series: Second Season", English: "Monogatari Series: Second Season", Year: 2013, Format: "TV"},
		20593:  {ID: 20593, Romaji: "Hanamonogatari", English: "Hanamonogatari", Year: 2014, Format: "TV"},
		9260:   {ID: 9260, Romaji: "Kizumonogatari I: Tekketsu-hen", English: "Kizumonogatari Part 1: Iron-Blooded", Year: 2016, Format: "MOVIE"},
		20918:  {ID: 20918, Romaji: "Tsukimonogatari", Year: 2014, Format: "TV"},
		21262:  {ID: 21262, Romaji: "Owarimonogatari", Year: 2015, Format: "TV"},
		21520:  {ID: 21520, Romaji: "Koyomimonogatari", Year: 2016, Format: "ONA"},
		100815: {ID: 100815, Romaji: "Zoku Owarimonogatari", Year: 2018, Format: "TV"},
	}
	var ids []int
	for id := range nodes {
		ids = append(ids, id)
	}
	return nodes, ids
}

func TestMonogatariIsNamedByItsSharedEnding(t *testing.T) {
	nodes, ids := monogatari()
	if name := Name(nodes, ids); name != "Monogatari" {
		t.Fatalf("named %q, want Monogatari", name)
	}
	if lead := Lead(nodes, ids); lead != 5081 {
		t.Fatalf("pictured by %d, want Bakemonogatari", lead)
	}
}

func TestSharedEndingNeedsMostTitles(t *testing.T) {
	nodes := map[int]Node{
		1: {ID: 1, Romaji: "Bakemonogatari", Year: 2009, Format: "TV"},
		2: {ID: 2, Romaji: "Umi Monogatari", Year: 2009, Format: "TV"},
		3: {ID: 3, Romaji: "Saiunkoku Monogatari", Year: 2006, Format: "TV"},
		4: {ID: 4, Romaji: "Princess Tutu", Year: 2002, Format: "TV"},
	}
	if name := Name(nodes, []int{1, 2, 3, 4}); name == "Monogatari" {
		t.Fatal("one title in four ending in -monogatari is no franchise name")
	}
}

func TestFolderYearIsNotPartOfTheName(t *testing.T) {
	results := []Node{{ID: 1, Romaji: "Kabukimonogatari", Year: 2013, Format: "TV"}}
	if n, ok := Match("Kabukimonogatari (2013)", "", 0, false, results); !ok || n.ID != 1 {
		t.Fatal("the year in a folder's name should be read as its year")
	}
	if _, ok := Match("Kabukimonogatari (2019)", "", 0, false, results); ok {
		t.Fatal("a folder's year still has to agree")
	}
	if name, year := CleanName("Mob Psycho 100 (II)"); name != "Mob Psycho 100 (II)" || year != 0 {
		t.Fatalf("a bracket that is not a year stays: %q %d", name, year)
	}
}

func TestShowMayBeFilmsOnlyWhenNoShowMatches(t *testing.T) {
	films := []Node{{ID: 9260, Romaji: "Kizumonogatari", Year: 2016, Format: "MOVIE"}}
	if n, ok := Match("Kizumonogatari (2016)", "", 2016, false, films); !ok || n.ID != 9260 {
		t.Fatal("a show folder of the films should match them")
	}
	both := append([]Node{{ID: 77, Romaji: "Kizumonogatari", Year: 2016, Format: "TV"}}, films...)
	if n, _ := Match("Kizumonogatari", "", 2016, false, both); n.ID != 77 {
		t.Fatal("a show matches a show first")
	}
}

func TestShowFolderOfFilmsMatchesTheFirstPart(t *testing.T) {
	films := []Node{
		{ID: 21399, Romaji: "Kizumonogatari II: Nekketsu-hen", Year: 2016, Format: "MOVIE"},
		{ID: 9260, Romaji: "Kizumonogatari I: Tekketsu-hen", Year: 2016, Format: "MOVIE"},
	}
	if n, ok := Match("Kizumonogatari (2016)", "", 2016, false, films); !ok || n.ID != 9260 {
		t.Fatalf("matched %d, want part one", n.ID)
	}
	if _, ok := Match("Kizumonogatari", "", 2016, true, films); ok {
		t.Fatal("a film keeps to exact names")
	}
	if firstPart("Kizumonogatari II: Nekketsu-hen", "Kizumonogatari") || firstPart("Kizumonogatarix I:", "Kizumonogatari") {
		t.Fatal("only the first part, of exactly that name")
	}
}

func TestFolderNamedLibrariesNameFranchisesByTheirFolders(t *testing.T) {
	nodes := map[int]Node{
		1: {ID: 1, Romaji: "Hoshi Paradise!", English: "Star Swap", Year: 2005, Format: "OVA"},
		2: {ID: 2, Romaji: "Hoshi Paradise! 2", Year: 2010, Format: "OVA"},
	}
	for folders, want := range map[string][]string{
		"Hoshi":              {"Hoshi", "Hoshi Twins"},
		"Kaze Yuugi":         {"Kaze Yuugi 2", "Kaze Yuugi"},
		"Neko Cosplay Kissa": {"Neko Cosplay Kissa 2", "Neko Cosplay Kissa 1"},
		"Tsubaki":            {"Tsubaki", "Tsubaki Reiwa Ban"},
	} {
		if got := NameFrom(nodes, []int{1, 2}, want); got != folders {
			t.Errorf("%v → %q, want %q", want, got, folders)
		}
	}
	// Folders that share nothing: the name most entries share in romaji, never the English.
	if got := NameFrom(nodes, []int{1, 2}, []string{"Triangle Green", "Deep Green"}); got != "Hoshi Paradise!" {
		t.Fatalf("romaji next: %q", got)
	}
	// A romaji library: no folders at all.
	if got := NameFrom(nodes, []int{1, 2}, nil); got != "Hoshi Paradise!" {
		t.Fatalf("romaji library: %q", got)
	}
}
