package api

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"os"
	"strconv"
	"time"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
	"lumiere-server/internal/subs"
)

// The subtitle queue's routes and its worker. See store/subqueue.go.

// defaultDailyLimit is what OpenSubtitles allows an API key with no account
// login: a handful a day. The owner can set their own in Settings.
const defaultDailyLimit = 5

const metaDailyLimit = "subtitle_daily_limit"

// Queue is POST /Shows/{seriesId}/Subtitles/Queue {"Language":"en","SeasonId":"…"}
// — "" for every season. Answers how many episodes were added.
func (h SubtitleHandler) Queue(w http.ResponseWriter, r *http.Request) {
	var body struct{ Language, SeasonId string }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<12)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	if body.Language == "" {
		body.Language = "en"
	}
	added, err := h.Store.QueueSubtitles(store.NormalizeID(r.PathValue("seriesId")),
		store.NormalizeID(body.SeasonId), body.Language)
	if err != nil {
		h.Log.Error("subtitles: could not queue", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not queue"})
		return
	}
	h.Log.Info("subtitles: queued", "episodes", added, "language", body.Language)
	writeJSON(w, http.StatusOK, map[string]any{"Added": added})
}

// QueueStatus is GET /Subtitles/Queue.
func (h SubtitleHandler) QueueStatus(w http.ResponseWriter, r *http.Request) {
	c, err := h.Store.SubtitleQueueStatus()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not read the queue"})
		return
	}
	shows, _ := h.Store.SubtitleQueueByShow()
	byShow := make([]map[string]any, 0, len(shows))
	for _, q := range shows {
		byShow = append(byShow, map[string]any{
			"Series": q.Series, "Waiting": q.Waiting, "Done": q.Done, "Failed": q.Failed,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"Waiting": c.Waiting, "Done": c.Done, "Failed": c.Failed,
		"DoneToday": c.DoneToday, "DailyLimit": h.dailyLimit(), "Shows": byShow,
	})
}

// RetryFailed is POST /Subtitles/Queue/Retry — everything not found goes back
// in the queue.
func (h SubtitleHandler) RetryFailed(w http.ResponseWriter, r *http.Request) {
	n, err := h.Store.RetryFailedSubtitles()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not retry"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"Retried": n})
}

// SetDailyLimit is POST /Subtitles/Queue/Limit {"DailyLimit": 5}.
func (h SubtitleHandler) SetDailyLimit(w http.ResponseWriter, r *http.Request) {
	var body struct{ DailyLimit int }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&body); err != nil ||
		body.DailyLimit < 1 || body.DailyLimit > 1000 {
		writeJSON(w, http.StatusBadRequest, errorBody{"a limit from 1 to 1000"})
		return
	}
	h.Store.SetMeta(metaDailyLimit, strconv.Itoa(body.DailyLimit))
	w.WriteHeader(http.StatusNoContent)
}

func (h SubtitleHandler) dailyLimit() int {
	v, _ := h.Store.Meta(metaDailyLimit)
	if n, err := strconv.Atoi(v); err == nil && n > 0 {
		return n
	}
	return defaultDailyLimit
}

// runQueue fetches what the day allows, then waits. Every half hour it looks
// again: a new day, a raised limit or a newly queued season all start it.
func (h SubtitleHandler) runQueue() {
	for {
		h.drainQueue()
		time.Sleep(30 * time.Minute)
	}
}

func (h SubtitleHandler) drainQueue() {
	key := subs.ReadKey(h.DataDir)
	if key == "" {
		return
	}
	h.retryWeekly()
	status, err := h.Store.SubtitleQueueStatus()
	if err != nil || status.Waiting == 0 {
		return
	}
	left := h.dailyLimit() - status.DoneToday
	if left <= 0 {
		return
	}
	next, err := h.Store.NextQueuedSubtitles(left)
	if err != nil {
		return
	}
	client := subs.New(key)
	for _, q := range next {
		state, note := h.fetchQueued(client, q)
		h.Store.FinishQueuedSubtitle(q.ItemID, q.Language, state, note)
		h.Log.Info("subtitles: queue", "item", q.ItemID, "state", state, "note", note)
		if client.Remaining == 0 {
			h.Log.Info("subtitles: provider's daily allowance used; the queue resumes tomorrow")
			return
		}
	}
}

// fetchQueued finds, fetches, syncs and files one episode's subtitle.
func (h SubtitleHandler) fetchQueued(client *subs.Client, q store.QueuedSubtitle) (state, note string) {
	item, err := h.Store.ItemByID(q.ItemID)
	if err != nil || item.Path == "" {
		return "failed", "the episode is gone"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	found, err := client.Search(ctx, h.queryFor(item, q.Language))
	if err != nil {
		return "failed", "search: " + err.Error()
	}
	best, ok := subs.Best(found)
	if !ok {
		return "failed", "nothing but machine translations, or nothing at all"
	}
	text, extension, err := client.Download(ctx, best.FileID)
	if err != nil {
		return "failed", "download: " + err.Error()
	}
	path := store.ExternalSubtitlePath(item.Path, q.Language, extension)
	if err := os.WriteFile(path, text, 0o644); err != nil {
		return "failed", "could not save beside the video"
	}

	// Synced where it can be, and the file itself corrected: a queued
	// subtitle is read by every player, not only the one that measured it.
	note = "saved; timing unchecked"
	if ffmpeg := media.FindFFmpeg(); ffmpeg != "" {
		offset, confidence, err := subs.Sync(ctx, ffmpeg, item.Path, path, 0, subs.MaxShift)
		switch {
		case err != nil:
			note = "saved; could not check timing"
		case confidence < subs.MinConfidence:
			note = fmt.Sprintf("saved; timing unsure (%.0f%%), left as is", confidence*100)
		case math.Abs(offset) < 0.3:
			note = "saved; already in time"
		default:
			if shifted, err := subs.Shift(text, extension, offset); err == nil &&
				os.WriteFile(path, shifted, 0o644) == nil {
				note = fmt.Sprintf("saved; shifted %+.1f s to the audio", offset)
			}
		}
	}
	if _, err := h.Store.AddExternalSubtitle(item.ID, path, q.Language, "OpenSubtitles"); err != nil {
		return "failed", "could not record the subtitle"
	}
	return "done", note
}

// queryFor is what to ask the provider for one item.
func (h SubtitleHandler) queryFor(item store.Item, language string) subs.Query {
	query := subs.Query{
		Language: language, Filename: item.Path,
		Title: item.Name, Year: deref(item.ProductionYear),
	}
	// A series' episode searches by its show, its season and its number:
	// the episode's own name is a translation away from whatever the
	// provider calls it, and the numbers are not.
	if item.SeriesID != "" {
		query.Title = item.SeriesName
		query.Season = deref(item.ParentIndexNumber)
		query.Episode = deref(item.IndexNumber)
		query.TmdbID = h.providerID(item.SeriesID)
	} else {
		query.TmdbID = h.providerID(item.ID)
	}
	return query
}

const metaLastRetry = "subtitle_last_retry"

// retryWeekly puts what was not found back in the queue once a week. A
// subtitle missing today is often uploaded within days of an episode airing,
// and asking again costs a search, not a download.
func (h SubtitleHandler) retryWeekly() {
	last, _ := h.Store.Meta(metaLastRetry)
	if when, err := time.Parse(time.RFC3339, last); err == nil && time.Since(when) < 7*24*time.Hour {
		return
	}
	if n, err := h.Store.RetryFailedSubtitles(); err == nil && n > 0 {
		h.Log.Info("subtitles: weekly retry of what was not found", "episodes", n)
	}
	h.Store.SetMeta(metaLastRetry, time.Now().UTC().Format(time.RFC3339))
}
