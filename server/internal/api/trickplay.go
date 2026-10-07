package api

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
)

// TrickplayRoot is where scrubbing previews are kept; set at start. See
// media.MakeTrickplay and the schedule package that makes them.
var TrickplayRoot string

// trickplayFor is the detail's Trickplay field for an item, or nil. Sheets
// made from an earlier version of the file are dropped here, so the next
// scheduled pass makes them again rather than a scrub showing the old cut.
func trickplayFor(s *store.Store, item store.Item) any {
	if TrickplayRoot == "" || item.Path == "" {
		return nil
	}
	info, ok := media.DecodeTrickplay(s.ItemValue(item.ID, "trickplay"))
	if !ok {
		return nil
	}
	if fp := media.VideoFingerprint(item.Path); fp != "" && info.Fingerprint != "" && fp != info.Fingerprint {
		s.SetItemValue(item.ID, "trickplay", "")
		os.RemoveAll(media.TrickplayDir(TrickplayRoot, item.ID))
		return nil
	}
	return map[string]map[string]media.TrickplayInfo{
		item.ID: {fmt.Sprint(info.Width): info},
	}
}

// Trickplay is GET /Videos/{id}/Trickplay/{width}/{file}: one tile sheet.
func Trickplay(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	width, err := strconv.Atoi(r.PathValue("width"))
	index, err2 := strconv.Atoi(strings.TrimSuffix(r.PathValue("file"), ".jpg"))
	if id == "" || err != nil || err2 != nil || width != media.TrickplayWidth || index < 0 {
		http.NotFound(w, r)
		return
	}
	path := filepath.Join(media.TrickplayDir(TrickplayRoot, id), fmt.Sprintf("%d.jpg", index))
	w.Header().Set("Cache-Control", "max-age=86400")
	w.Header().Set("Content-Type", "image/jpeg")
	http.ServeFile(w, r, path)
}
