package api

import (
	"testing"

	"lumiere-server/internal/store"
)

// An episode's ParentId must be its season and a season's its series, because
// that is what Jellyfin reports and what the client lists by. See logicalParent.
func TestLogicalParent(t *testing.T) {
	cases := []struct {
		name string
		item store.Item
		want string
	}{
		{"episode reports its season, not the folder it sits in",
			store.Item{Type: "Episode", ParentID: "folder", SeasonID: "season", SeriesID: "series"},
			"season"},
		{"season reports its series",
			store.Item{Type: "Season", ParentID: "folder", SeriesID: "series"},
			"series"},
		{"an episode with no season keeps the parent it has",
			store.Item{Type: "Episode", ParentID: "folder"},
			"folder"},
		{"anything else is untouched",
			store.Item{Type: "Movie", ParentID: "folder"},
			"folder"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := logicalParent(c.item); got != c.want {
				t.Errorf("logicalParent = %q, want %q", got, c.want)
			}
		})
	}
}
