package api

import (
	"errors"
	"net/http"
	"strings"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/scanner"
	"lumiere-server/internal/store"
)

// ItemDetail is GET /Users/{userId}/Items/{id} — the legacy path, and the one
// Lumiere uses. It never calls /Items/{id}.
//
// The same item as a list row, plus the things a list deliberately omits:
// MediaSources, MediaStreams, Chapters and People. The capture shows 65 keys
// here against roughly 25 in a list, and no list response carries MediaSources
// at all — loading them for a 200-row page would be 200 items' worth of tracks
// nobody asked for.
func (h ItemsHandler) ItemDetail(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" {
		http.NotFound(w, r)
		return
	}
	item, err := h.Store.ItemByID(id)
	if err != nil {
		if !errors.Is(err, store.ErrNoItem) {
			h.Log.Error("detail lookup failed", "error", err, "item", id)
		}
		http.NotFound(w, r)
		return
	}

	b, err := h.detail(item)
	if err != nil {
		h.Log.Error("detail assembly failed", "error", err, "item", id)
		writeJSON(w, http.StatusInternalServerError, errorBody{"detail failed"})
		return
	}
	writeJSON(w, http.StatusOK, b)
}

// detail decorates a wire item with everything the detail field set asks for.
func (h ItemsHandler) detail(item store.Item) (jellyfin.BaseItem, error) {
	b := ToWire(item, h.Identity.ServerID)

	credits, err := h.Store.Credits(item.ID)
	if err != nil {
		return b, err
	}
	ids := make([]string, 0, len(credits))
	for _, c := range credits {
		ids = append(ids, c.PersonID)
	}
	portraits, err := h.Store.PrimaryTags(ids)
	if err != nil {
		return b, err
	}
	for _, c := range credits {
		b.People = append(b.People, jellyfin.Person{
			Id: c.PersonID, Name: c.Name, Role: c.Role, Type: c.Type,
			PrimaryImageTag: portraits[c.PersonID],
		})
	}

	chapters, err := h.Store.Chapters(item.ID)
	if err != nil {
		return b, err
	}
	for _, c := range chapters {
		b.Chapters = append(b.Chapters, jellyfin.Chapter{
			StartPositionTicks: c.StartTicks, Name: c.Name,
		})
	}

	// Only things that are actually a file get a MediaSource. A series or a
	// season has no path and no streams, and emitting an empty source for one
	// would offer the client something to try to play.
	if item.Path == "" || item.IsFolder {
		return b, nil
	}
	streams, err := h.Store.Streams(item.ID)
	if err != nil {
		return b, err
	}
	// Never read: read it now, a tenth of a second, so the player has tracks
	// to name and a TV has formats to check before it tries.
	if len(streams) == 0 {
		if tool := scanner.FindFFprobe(); tool != "" {
			if rows, err := scanner.ProbeStreams(tool, item.Path); err == nil && len(rows) > 0 {
				h.Store.WriteStreams(item.ID, rows)
				streams, _ = h.Store.Streams(item.ID)
			}
		}
	}
	// Subtitle files beside the video, found as it is opened: an MP4 with an
	// .srt in its folder gets that subtitle offered like any other.
	if h.Store.LinkSidecarSubtitles(item.ID, item.Path, streams) {
		streams, _ = h.Store.Streams(item.ID)
	}
	source := mediaSource(item, streams)
	b.MediaSources = []jellyfin.MediaSource{source}
	b.MediaStreams = source.MediaStreams
	b.Trickplay = trickplayFor(h.Store, item)
	return b, nil
}

// mediaSource builds the object the whole playback decision is made from.
//
// The Id is the item's own id, not a separate one. Jellyfin mints a distinct
// media source id per version of a file; this server serves one file per item,
// so reusing the item id means the mediaSourceId that comes back on every
// stream URL and progress report is already the key everything else is stored
// under.
func mediaSource(item store.Item, streams []store.Stream) jellyfin.MediaSource {
	src := jellyfin.MediaSource{
		Id:        item.ID,
		Name:      item.Name,
		Path:      item.Path,
		Protocol:  "File",
		Type:      "Default",
		Container: strings.ToLower(item.Container),
		// Constants rather than a computation. Lumiere decodes all three and
		// throws them away — it builds its own URLs and decides for itself — and
		// the spec says a replacement server need not compute them. Direct play
		// is the truth for every file this server serves, since it never
		// transcodes; SupportsTranscoding stays true so a client that asks is
		// told plainly by the 503 rather than never asking at all.
		SupportsDirectPlay:   true,
		SupportsDirectStream: true,
		SupportsTranscoding:  true,
		SupportsProbing:      true,
		VideoType:            "VideoFile",
		RunTimeTicks:         item.RuntimeTicks,
	}
	if item.Size > 0 {
		size := item.Size
		src.Size = &size
	}
	if item.TotalBitrate > 0 {
		// Required whenever a bitrate cap is set: it is the only thing the client
		// compares the cap against, and without it a capped client either always
		// transcodes or never does.
		rate := item.TotalBitrate
		src.Bitrate = &rate
	}

	for _, st := range streams {
		src.MediaStreams = append(src.MediaStreams, wireStream(st))
	}
	// The tracks the client should start on. These are the per-item choices
	// Jellyfin recorded and the import carried over; Lumiere keeps its own copy
	// too, but a fresh install has none and would otherwise start on stream 0.
	src.DefaultAudioStreamIndex = defaultIndex(streams, "Audio", item.AudioIndex)
	src.DefaultSubtitleStreamIndex = defaultIndex(streams, "Subtitle", item.SubtitleIndex)
	return src
}

// defaultIndex prefers the remembered choice, then the track flagged default in
// the file, then nothing. Returning an index that is not in the file would be
// worse than returning none: the client would select a track that cannot exist.
func defaultIndex(streams []store.Stream, kind string, remembered *int) *int {
	if remembered != nil {
		for _, st := range streams {
			if st.Index == *remembered && st.Type == kind {
				n := *remembered
				return &n
			}
		}
	}
	for _, st := range streams {
		if st.Type == kind && st.IsDefault {
			n := st.Index
			return &n
		}
	}
	// Nothing flagged default. Jellyfin still names one for audio, and so does
	// this: the capture shows a file whose only audio stream has IsDefault
	// false, and a player given no index either falls back to the first track
	// or starts silent depending on which player it is. Lumiere happens to fall
	// back; not every client does.
	//
	// Subtitles get no such fallback, deliberately: no flagged subtitle means
	// none should be on, and picking the first would turn subtitles on for
	// everyone who never asked.
	if kind == "Audio" {
		for _, st := range streams {
			if st.Type == kind {
				n := st.Index
				return &n
			}
		}
	}
	return nil
}

func wireStream(st store.Stream) jellyfin.MediaStream {
	return jellyfin.MediaStream{
		Index: st.Index, Type: st.Type, Codec: st.Codec,
		Language: st.Language, Title: st.Title, DisplayTitle: st.Display,
		IsDefault: st.IsDefault, IsForced: st.IsForced, IsExternal: st.IsExternal,
		Width: st.Width, Height: st.Height, BitDepth: st.BitDepth,
		Profile: st.Profile, VideoRange: st.VideoRange,
		VideoRangeType: st.VideoRangeTyp,
		DvProfile:      st.DvProfile, DvLevel: st.DvLevel,
		AverageFrameRate: st.AvgFrameRate, RealFrameRate: st.FrameRate,
		Channels: st.Channels, SampleRate: st.SampleRate,
		ChannelLayout: st.ChannelLayout, BitRate: st.BitRate,
		Path: st.Path,
	}
}
