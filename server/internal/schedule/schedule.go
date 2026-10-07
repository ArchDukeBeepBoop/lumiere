// Package schedule runs the server's background work on its own: a scan of
// the disk every few hours, and scrubbing previews made in the quiet hours.
//
// Both wait while anything is playing. The scan is cheap but sets off the
// naming and frame passes behind it; the previews decode whole files. Neither
// should be the reason the fans come on halfway through a film.
package schedule

import (
	"log/slog"
	"sync"
	"time"

	"lumiere-server/internal/api"
	"lumiere-server/internal/media"
	"lumiere-server/internal/scanner"
	"lumiere-server/internal/store"
)

// Scanner is the one thing this needs from the scan button's handler.
type Scanner interface {
	StartScan() error
	Scanning() bool
}

type Keeper struct {
	Store         *store.Store
	Log           *slog.Logger
	Scan          Scanner
	TrickplayRoot string

	wake chan struct{}
	mu   sync.Mutex
	// now is set by PreviewsNow: make previews outside the quiet hours, once.
	now     bool
	working string
}

const (
	tick             = 5 * time.Minute
	playingFor       = 3 * time.Minute
	metaLastAutoScan = "auto_scan_at"
)

func (k *Keeper) Start() {
	k.wake = make(chan struct{}, 1)
	go func() {
		for {
			select {
			case <-time.After(tick):
			case <-k.wake:
			}
			k.runOnce(time.Now())
		}
	}()
}

// PreviewsNow makes previews straight away, whatever the hour, until there
// are none left to make. Still not while something plays.
func (k *Keeper) PreviewsNow() {
	k.mu.Lock()
	k.now = true
	k.mu.Unlock()
	select {
	case k.wake <- struct{}{}:
	default:
	}
}

// Status is what Settings shows.
type Status struct {
	store.ServerSettings
	PreviewsMade  int
	PreviewsTotal int
	Working       string `json:",omitempty"`
	LastAutoScan  string `json:",omitempty"`
	Waiting       string `json:",omitempty"`
	// Addresses the home network reaches the server at, when it is shared.
	Addresses []string `json:",omitempty"`
	// WakeAddress is the hardware address of the network the server is
	// shared on, for a TV to send wake-on-LAN to a sleeping Mac.
	WakeAddress string `json:",omitempty"`
}

func (k *Keeper) Status() Status {
	s := Status{ServerSettings: k.Store.Settings()}
	s.PreviewsMade, s.PreviewsTotal = k.Store.PreviewCounts()
	s.LastAutoScan, _ = k.Store.Meta(metaLastAutoScan)
	if s.ListensOnNetwork {
		s.Addresses = api.Addresses()
		s.WakeAddress = api.WakeAddress()
	}
	k.mu.Lock()
	s.Working = k.working
	k.mu.Unlock()
	if k.Store.RecentlyPlaying(playingFor) {
		s.Waiting = "something is playing"
	}
	return s
}

func (k *Keeper) runOnce(now time.Time) {
	if k.Store.RecentlyPlaying(playingFor) {
		return
	}
	settings := k.Store.Settings()
	k.maybeScan(settings, now)
	// Tracks for files only the scanner knows, fifty a tick — about five
	// seconds of ffprobe — until there are none left.
	if !k.Scan.Scanning() {
		if n := scanner.FillStreams(k.Store, 50); n > 0 {
			k.Log.Info("tracks read for files that had none", "count", n)
		}
	}
	k.mu.Lock()
	forced := k.now
	k.mu.Unlock()
	if settings.MakesPreviews && (forced || settings.InQuietHours(now)) && !k.Scan.Scanning() {
		if made := k.previews(settings, forced, now.Add(tick-30*time.Second)); made == 0 {
			k.mu.Lock()
			k.now = false
			k.mu.Unlock()
		}
	}
}

func (k *Keeper) maybeScan(settings store.ServerSettings, now time.Time) {
	if settings.ScanEveryHours == 0 || k.Scan.Scanning() {
		return
	}
	last, _ := k.Store.Meta(metaLastAutoScan)
	if t, err := time.Parse(time.RFC3339, last); err == nil &&
		now.Sub(t) < time.Duration(settings.ScanEveryHours)*time.Hour {
		return
	}
	k.Store.SetMeta(metaLastAutoScan, now.UTC().Format(time.RFC3339))
	if err := k.Scan.StartScan(); err != nil {
		k.Log.Info("scheduled scan: skipped", "reason", err)
		return
	}
	k.Log.Info("scheduled scan started")
}

// previews makes them one file at a time until the deadline, the quiet hours
// end, or something starts playing. Returns how many it made.
func (k *Keeper) previews(settings store.ServerSettings, forced bool, deadline time.Time) int {
	ffmpeg := media.FindFFmpeg()
	if ffmpeg == "" || k.TrickplayRoot == "" {
		return 0
	}
	files, err := k.Store.PreviewCandidates(20)
	if err != nil || len(files) == 0 {
		return 0
	}
	made := 0
	defer func() {
		k.mu.Lock()
		k.working = ""
		k.mu.Unlock()
	}()
	for _, f := range files {
		now := time.Now()
		if now.After(deadline) || k.Store.RecentlyPlaying(playingFor) ||
			(!forced && !settings.InQuietHours(now)) {
			break
		}
		k.mu.Lock()
		k.working = f.Path
		k.mu.Unlock()
		info, err := media.MakeTrickplay(ffmpeg, f.Path, f.RuntimeSeconds, media.TrickplayDir(k.TrickplayRoot, f.ID))
		if err != nil {
			k.Log.Info("previews: could not make", "file", f.Path, "error", err)
			k.Store.PreviewFailed(f.ID, media.VideoFingerprint(f.Path))
			continue
		}
		k.Store.SetItemValue(f.ID, "trickplay", media.EncodeTrickplay(info))
		made++
	}
	if made > 0 {
		k.Log.Info("previews made", "count", made)
	}
	return made
}
