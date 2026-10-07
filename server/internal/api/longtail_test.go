package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"lumiere-server/internal/store"
)

// A real-shaped id: NormalizeID shape-checks for 32 hex characters, so a
// friendly "ep1" is rejected before the handler ever runs.
const testItemID = "4130243b9d4bc468a0c7ac1bd58fca2c"

func segmentHandler(t *testing.T) ItemsHandler {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	for _, seg := range []struct {
		kind        string
		start, stop int64
	}{
		{"Intro", 0, 1_000_000_000},
		{"Outro", 9_000_000_000, 9_900_000_000},
		{"Recap", 2_000_000_000, 2_500_000_000},
	} {
		if _, err := s.DB.Exec(
			`INSERT INTO segment (item_id, type, start_ticks, end_ticks) VALUES (?,?,?,?)`,
			testItemID, seg.kind, seg.start, seg.stop); err != nil {
			t.Fatal(err)
		}
	}
	return ItemsHandler{Store: s, Log: slog.New(slog.DiscardHandler)}
}

func segmentTypes(t *testing.T, h ItemsHandler, query string) []string {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, "/MediaSegments/"+testItemID+"?"+query, nil)
	r.SetPathValue("id", testItemID)
	w := httptest.NewRecorder()
	h.MediaSegments(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("status %d", w.Code)
	}
	body, _ := io.ReadAll(w.Body)
	var resp segmentsResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, s := range resp.Items {
		out = append(out, s.Type)
	}
	return out
}

// The parameter is repeated, not comma-joined, and reading only the first value
// is the bug that silently killed Skip Intro across a whole library: every
// episode kept its intro mark and lost its outro, which looks like missing data
// rather than a parsing mistake.
func TestMediaSegmentsReadsRepeatedParameters(t *testing.T) {
	h := segmentHandler(t)

	got := segmentTypes(t, h, "includeSegmentTypes=Intro&includeSegmentTypes=Outro")
	if len(got) != 2 {
		t.Fatalf("got %v, want both Intro and Outro", got)
	}

	if got := segmentTypes(t, h, "includeSegmentTypes=Intro"); len(got) != 1 || got[0] != "Intro" {
		t.Fatalf("got %v, want just Intro", got)
	}

	// No filter means every type, not none — an easy thing to get backwards, and
	// getting it backwards makes the skip buttons vanish rather than error.
	if got := segmentTypes(t, h, ""); len(got) != 3 {
		t.Fatalf("got %v, want all three", got)
	}
}

// Jellyfin rejects a comma-joined list; being lenient where the strict server
// is not cannot break a client that is already correct.
func TestMediaSegmentsAlsoAcceptsAJoinedList(t *testing.T) {
	h := segmentHandler(t)
	if got := segmentTypes(t, h, "includeSegmentTypes=Intro,Outro"); len(got) != 2 {
		t.Fatalf("got %v, want two", got)
	}
}

func TestMediaSegmentsIsCaseInsensitive(t *testing.T) {
	h := segmentHandler(t)
	if got := segmentTypes(t, h, "IncludeSegmentTypes=Intro"); len(got) != 1 {
		t.Fatalf("got %v, want one", got)
	}
}
