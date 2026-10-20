package api

import (
	"encoding/json"
	"fmt"
	"net/http"

	"lumiere-server/internal/store"
)

// The desktop widget's feed: Continue Watching, read-only, for the widget
// on this Mac. A widget runs sandboxed and cannot reach the app's sign-in,
// so it asks here without a token — which is why this answers loopback
// only, never lists anything from a private library, and can be switched
// off from the Mac's Settings.
type WidgetHandler struct {
	Store  *store.Store
	Images http.HandlerFunc
}

const metaWidgetOff = "widget_off"

// Register adds the public, loopback-only routes and the authed switch.
func (h WidgetHandler) Register(public, authed *http.ServeMux) {
	public.HandleFunc("GET /Lumiere/Widget", h.loopback(h.Feed))
	public.HandleFunc("GET /Lumiere/Widget/Items/{id}/Images/{kind}", h.loopback(h.Images))
	authed.HandleFunc("POST /Lumiere/Widget/Enabled", h.SetEnabled)
}

func (h WidgetHandler) loopback(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !fromLoopback(r) {
			writeJSON(w, http.StatusForbidden, errorBody{"this Mac only"})
			return
		}
		if off, _ := h.Store.Meta(metaWidgetOff); off == "1" {
			writeJSON(w, http.StatusOK, map[string]any{"Items": []any{}})
			return
		}
		next(w, r)
	}
}

// WidgetItem is one tile.
type WidgetItem struct {
	ID       string  `json:"Id"`
	Title    string  `json:"Title"`
	Subtitle string  `json:"Subtitle"`
	Progress float64 `json:"Progress"`
}

// Feed is GET /Lumiere/Widget: up to four titles to resume.
func (h WidgetHandler) Feed(w http.ResponseWriter, r *http.Request) {
	items, err := h.Store.Resume(true, 20)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	raw, _ := h.Store.Meta(metaPrivateLibraries)
	rooms := h.Store.LibraryRooms(splitList(raw))
	out := []WidgetItem{}
	for _, it := range items {
		if rooms.Private[it.LibraryID] || len(out) == 4 {
			continue
		}
		tile := WidgetItem{ID: it.ID, Title: it.Name}
		if it.SeriesName != "" {
			tile.Title = it.SeriesName
			tile.Subtitle = it.Name
			if it.ParentIndexNumber != nil && it.IndexNumber != nil {
				tile.Subtitle = fmt.Sprintf("S%d E%d · %s", *it.ParentIndexNumber, *it.IndexNumber, it.Name)
			}
		}
		if it.UserData != nil && it.RuntimeTicks != nil && *it.RuntimeTicks > 0 {
			tile.Progress = float64(it.UserData.PositionTicks) / float64(*it.RuntimeTicks)
		}
		out = append(out, tile)
	}
	writeJSON(w, http.StatusOK, map[string]any{"Items": out})
}

// SetEnabled is POST /Lumiere/Widget/Enabled {"Enabled": bool}.
func (h WidgetHandler) SetEnabled(w http.ResponseWriter, r *http.Request) {
	var body struct{ Enabled bool }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"expected {\"Enabled\": bool}"})
		return
	}
	value := "0"
	if !body.Enabled {
		value = "1"
	}
	h.Store.SetMeta(metaWidgetOff, value)
	w.WriteHeader(http.StatusNoContent)
}
