package api

import (
	"testing"

	"lumiere-server/internal/anilist"
)

func TestFranchiseArtIsTheLeadCoverAndTheFirstBanner(t *testing.T) {
	nodes := map[int]anilist.Node{
		5081:  {ID: 5081, Romaji: "Bakemonogatari", Year: 2009, Format: "TV", Cover: "https://s4.anilist.co/c/bake.jpg", Banner: anilist.NoBanner},
		11597: {ID: 11597, Romaji: "Nisemonogatari", Year: 2012, Format: "TV", Banner: "https://s4.anilist.co/b/nise.jpg"},
		100:   {ID: 100, Romaji: "Bakemonogatari Recap", Year: 2009, Format: "SPECIAL", Banner: "https://s4.anilist.co/b/recap.jpg"},
	}
	art := franchiseArtFor(nodes, []int{100, 5081, 11597})
	if art.Cover != "https://s4.anilist.co/c/bake.jpg" {
		t.Fatalf("poster %q", art.Cover)
	}
	// The recap came out first, so its banner is the earliest one there is.
	if art.Banner != "https://s4.anilist.co/b/recap.jpg" {
		t.Fatalf("backdrop %q", art.Banner)
	}
	if artTag(art.Cover) == artTag(art.Banner) || artTag(art.Cover)[:7] != "anilist" {
		t.Fatal("tags name their picture")
	}
}
