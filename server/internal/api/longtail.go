package api

import (
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// MediaSegment is one skip mark on the wire.
type MediaSegment struct {
	Id         string `json:"Id"`
	ItemId     string `json:"ItemId"`
	Type       string `json:"Type"`
	StartTicks int64  `json:"StartTicks"`
	EndTicks   int64  `json:"EndTicks"`
}

type segmentsResponse struct {
	Items            []MediaSegment `json:"Items"`
	TotalRecordCount int            `json:"TotalRecordCount"`
	StartIndex       int            `json:"StartIndex"`
}

// MediaSegments is GET /MediaSegments/{id} — the Skip Intro data.
//
// The types arrive as **repeated** parameters, not a comma-joined list:
// ?includeSegmentTypes=Intro&includeSegmentTypes=Outro&... Jellyfin 400s a
// joined list, and doing that once silently killed Skip Intro across the whole
// library — so `r.URL.Query()["includeSegmentTypes"]` is the whole point of
// this handler, and reading only the first value would quietly drop every type
// after Intro.
func (h ItemsHandler) MediaSegments(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		http.NotFound(w, r)
		return
	}
	// Case-insensitively, and accepting a comma-joined list too. Jellyfin would
	// reject the joined form; being lenient where the strict server is not costs
	// nothing and cannot break a client that is already correct.
	var types []string
	for key, values := range r.URL.Query() {
		if !equalFoldASCII(key, "includeSegmentTypes") {
			continue
		}
		for _, v := range values {
			types = append(types, splitList(v)...)
		}
	}

	segments, err := h.Store.Segments(id, types)
	if err != nil {
		h.Log.Error("media segments failed", "error", err, "item", id)
		http.NotFound(w, r)
		return
	}
	// The file's own chapter names fill in whatever kinds the analysis did
	// not find — all of them for a file never analysed, and a recap for
	// almost everything. See store.ChapterSegments.
	if chapters, err := h.Store.Chapters(id); err == nil && len(chapters) > 0 {
		if item, err := h.Store.ItemByID(id); err == nil {
			segments = store.FillMissingTypes(segments, store.OnlyTypes(
				store.ChapterSegments(id, chapters, deref64(item.RuntimeTicks)), types))
		}
	}

	out := make([]MediaSegment, 0, len(segments))
	for i, seg := range segments {
		out = append(out, MediaSegment{
			// Segments have no id of their own in Intro Skipper's data, and the
			// client ignores this field. A stable synthetic one beats an empty
			// string, which some decoders treat as a missing key.
			Id:         seg.ItemID + "-" + itoa(i),
			ItemId:     seg.ItemID,
			Type:       seg.Type,
			StartTicks: seg.StartTicks,
			EndTicks:   seg.EndTicks,
		})
	}
	// The envelope, not a bare list — verified in §12.6.
	writeJSON(w, http.StatusOK, segmentsResponse{
		Items: out, TotalRecordCount: len(out),
	})
}

// Resume is GET /UserItems/Resume — Continue Watching.
//
// Load-bearing per §8's list, and it belonged to no batch in the plan. Without
// it the shelf is permanently empty, which is exactly the error state this
// batch is meant to eliminate.
func (h ItemsHandler) Resume(w http.ResponseWriter, r *http.Request) {
	get := caseInsensitive(r.URL.Query())
	videoOnly := equalFoldASCII(get("MediaTypes"), "Video")
	items, err := h.Store.Resume(videoOnly, atoiOr(get("Limit"), 20))
	if err != nil {
		h.Log.Error("resume failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items: h.wire(items), TotalRecordCount: len(items),
	})
}

// Latest is GET /Items/Latest — recently added.
//
// **A bare JSON array, not an envelope.** One of the two endpoints that differ
// this way (§5.1); wrapping it means the client decodes nothing and the shelf
// is silently empty rather than broken.
func (h ItemsHandler) Latest(w http.ResponseWriter, r *http.Request) {
	get := caseInsensitive(r.URL.Query())
	var libraries []string
	if parent := store.NormalizeID(get("ParentId")); parent != "" {
		// The client asks per library, and the id it sends is the view's — which
		// is not what the items carry. Same resolution the recursive /Items path
		// needs, and the same reason.
		folders, err := h.Store.LibraryFolders(parent)
		if err != nil {
			h.Log.Error("latest library lookup failed", "error", err)
			writeJSON(w, http.StatusOK, []jellyfin.BaseItem{})
			return
		}
		libraries = folders
		if len(libraries) == 0 {
			libraries = []string{parent}
		}
	}
	items, err := h.Store.Latest(libraries, atoiOr(get("Limit"), 20))
	if err != nil {
		h.Log.Error("latest failed", "error", err)
		writeJSON(w, http.StatusOK, []jellyfin.BaseItem{})
		return
	}
	writeJSON(w, http.StatusOK, h.wire(items))
}

// ScheduledTasks is asked for 13 times in the capture and this server has none.
//
// An empty array rather than a 404: the endpoint is real on Jellyfin and a
// client that lists tasks should see an empty list, not a missing feature.
func (h ItemsHandler) ScheduledTasks(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, []struct{}{})
}

func deref64(value *int64) int64 {
	if value == nil {
		return 0
	}
	return *value
}
