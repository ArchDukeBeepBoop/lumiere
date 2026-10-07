package metadata

import "testing"

func TestBestPrefersTheYearTheFolderStates(t *testing.T) {
	candidates := []Candidate{
		{ID: "remake", Title: "Blade Runner", Year: 2017, Popularity: 90},
		{ID: "original", Title: "Blade Runner", Year: 1982, Popularity: 40},
	}
	best, ok := Best("Blade Runner", 1982, candidates)
	if !ok || best.ID != "original" {
		t.Errorf("got %+v; the folder said 1982", best)
	}
}

func TestBestMatchesAcrossPunctuation(t *testing.T) {
	// The case that split twenty-five shows in the scanner: the folder is
	// `Dr Stone` and the provider says `Dr. STONE`.
	best, ok := Best("Dr Stone", 0, []Candidate{{ID: "1", Title: "Dr. STONE", Year: 2019}})
	if !ok || best.ID != "1" {
		t.Errorf("got %+v, %v; want the normalised match", best, ok)
	}
}

func TestBestRefusesAWeakMatch(t *testing.T) {
	// The failure this exists to prevent: a wrong match does not error, it
	// silently renames a show and hangs the wrong poster on it.
	_, ok := Best("Blade", 0, []Candidate{
		{ID: "1", Title: "Blade Runner", Popularity: 99},
		{ID: "2", Title: "Blade Runner 2049", Popularity: 95},
	})
	if ok {
		t.Error("a title that merely shares a word is not a match")
	}
}

func TestBestOnNothing(t *testing.T) {
	if _, ok := Best("Anything", 0, nil); ok {
		t.Error("no candidates is no match")
	}
}

func TestBestBreaksTiesWithinATierOnly(t *testing.T) {
	// Two exact matches, no year to separate them: popularity decides.
	best, ok := Best("Ghost", 0, []Candidate{
		{ID: "quiet", Title: "Ghost", Popularity: 2},
		{ID: "loud", Title: "Ghost", Popularity: 80},
	})
	if !ok || best.ID != "loud" {
		t.Errorf("got %+v", best)
	}

	// But popularity must not cross tiers: an exact match with the wrong year
	// still beats a merely-normalised one, however famous.
	best, ok = Best("Ghost", 1990, []Candidate{
		{ID: "exact", Title: "Ghost", Year: 2019, Popularity: 1},
		{ID: "normalised", Title: "The Ghost", Year: 1990, Popularity: 99},
	})
	if !ok || best.ID != "exact" {
		t.Errorf("got %+v, want the exact title", best)
	}
}

func TestNormalise(t *testing.T) {
	cases := [][2]string{
		{"Dr. STONE", "dr stone"},
		{"The Matrix", "matrix"},
		{"Attack on Titan: Final Season", "attack on titan final season"},
		{"86 Eighty-Six", "86 eighty six"},
	}
	for _, c := range cases {
		if got := Normalise(c[0]); got != c[1] {
			t.Errorf("Normalise(%q) = %q, want %q", c[0], got, c[1])
		}
	}
	// Digits stay: dropping them would merge Season 2 into Season.
	if Normalise("Season 2") == Normalise("Season 3") {
		t.Error("two different seasons must not normalise to one string")
	}
}
