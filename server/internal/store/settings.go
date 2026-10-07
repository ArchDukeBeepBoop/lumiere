package store

import (
	"encoding/json"
	"time"
)

// ServerSettings are the choices that belong to the server rather than to one
// client: when something counts as watched, how long Continue Watching holds
// on to it, and when the heavy background work is allowed to run. Kept as one
// JSON value in meta, read fresh each time — they change from Settings while
// the server runs, and a stale copy would make the switch look broken.
type ServerSettings struct {
	// WatchedPercent is how far into a file it counts as watched. Jellyfin and
	// Plex both use 90, which is also where the credits start on most things.
	WatchedPercent int
	// ResumeWeeks is how long a started file stays on Continue Watching after
	// it was last played. Zero keeps it until it is finished.
	ResumeWeeks int
	// ScanEveryHours looks at the disk on its own this often. Zero is never.
	ScanEveryHours int
	// QuietFrom and QuietTo are the hours, 0–23, preview making is allowed
	// in — a whole-file decode per video. Equal means any hour. Scans are a
	// walk of the disk and run at any hour nothing is playing.
	QuietFrom int
	QuietTo   int
	// MakesPreviews makes scrubbing previews for files that have none.
	MakesPreviews bool
	// ListensOnNetwork serves the library to the home network as well as to
	// this Mac — how a phone or TV reaches it. Off unless turned on.
	ListensOnNetwork bool
	// BlockedAddresses are home-network devices refused outright, before
	// sign-in — a device that should never see even the server's name.
	BlockedAddresses []string
	// AutoCollections makes a collection of every film series with two or
	// more films here, room by room, daily. See api.AutoCollections.
	AutoCollections bool
}

const metaServerSettings = "server_settings"

// DefaultServerSettings is what an untouched server does: the behaviour it
// had before any of this was a setting, plus a nightly scan and previews made
// in the small hours.
func DefaultServerSettings() ServerSettings {
	return ServerSettings{
		WatchedPercent: 90, ScanEveryHours: 6,
		QuietFrom: 1, QuietTo: 7, MakesPreviews: true, AutoCollections: true,
	}
}

// Settings reads them, filling anything missing or out of range with the
// default rather than failing — a typo in one field must not stop the server.
func (s *Store) Settings() ServerSettings {
	out := DefaultServerSettings()
	if raw, _ := s.Meta(metaServerSettings); raw != "" {
		json.Unmarshal([]byte(raw), &out)
	}
	return out.clamped()
}

func (s *Store) SetSettings(v ServerSettings) (ServerSettings, error) {
	v = v.clamped()
	raw, _ := json.Marshal(v)
	return v, s.SetMeta(metaServerSettings, string(raw))
}

func (v ServerSettings) clamped() ServerSettings {
	d := DefaultServerSettings()
	if v.WatchedPercent < 50 || v.WatchedPercent > 100 {
		v.WatchedPercent = d.WatchedPercent
	}
	if v.ResumeWeeks < 0 {
		v.ResumeWeeks = 0
	}
	if v.ScanEveryHours < 0 {
		v.ScanEveryHours = 0
	}
	if v.QuietFrom < 0 || v.QuietFrom > 23 {
		v.QuietFrom = d.QuietFrom
	}
	if v.QuietTo < 0 || v.QuietTo > 23 {
		v.QuietTo = d.QuietTo
	}
	return v
}

// InQuietHours says whether heavy work may run at t. A window that wraps
// midnight (22 to 6) is read the way anyone would read it.
func (v ServerSettings) InQuietHours(t time.Time) bool {
	h := t.Hour()
	switch {
	case v.QuietFrom == v.QuietTo:
		return true
	case v.QuietFrom < v.QuietTo:
		return h >= v.QuietFrom && h < v.QuietTo
	default:
		return h >= v.QuietFrom || h < v.QuietTo
	}
}

// RecentlyPlaying says whether any player has reported in the last few
// minutes. Background work waits it out: decoding a whole file for previews
// while a film plays is exactly the fan noise the thermal rule is about.
func (s *Store) RecentlyPlaying(within time.Duration) bool {
	since := time.Now().UTC().Add(-within).Format(time.RFC3339Nano)
	var n int
	s.DB.QueryRow(`SELECT count(*) FROM user_data WHERE source = 'local' AND updated_at > ?`,
		since).Scan(&n)
	return n > 0
}

// FinishIfWatched marks an item watched when a stop lands past
// WatchedPercent of it, as Jellyfin and Plex do. The client marks at the
// credits itself; this covers a player that stops short of them, or a
// client that does not mark at all. Reports whether it marked anything.
func (s *Store) FinishIfWatched(itemID string, positionTicks int64) bool {
	var runtime int64
	var played int
	s.DB.QueryRow(`SELECT COALESCE(i.runtime_ticks, 0), COALESCE(u.played, 0)
		FROM item i LEFT JOIN user_data u ON u.item_id = i.id
		WHERE i.id = ? AND i.is_folder = 0 AND i.extra_type IS NULL`, itemID).Scan(&runtime, &played)
	if runtime <= 0 || played == 1 || positionTicks*100 < runtime*int64(s.Settings().WatchedPercent) {
		return false
	}
	return s.SetPlayed(itemID, true) == nil
}
