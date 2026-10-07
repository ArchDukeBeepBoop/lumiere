package main

import (
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"lumiere-server/internal/store"
)

// GET /Lumiere/Changes?since=N[&wait=S][&limit=L]
//
// What changed in the library after change N: {Next, Reset, Changed, Removed,
// More}. With wait, the request is held up to S seconds (at most 55) until
// something changes, so a client hears of a change within a second without
// polling. See store.ChangesSince.
func registerChanges(authed *http.ServeMux, db *store.Store, log *slog.Logger) {
	go func() {
		for {
			if err := db.TrimChanges(); err != nil {
				log.Info("change log: could not trim", "error", err)
			}
			time.Sleep(6 * time.Hour)
		}
	}()
	authed.HandleFunc("GET /Lumiere/Changes", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		since, _ := strconv.ParseInt(q.Get("since"), 10, 64)
		limit, _ := strconv.Atoi(q.Get("limit"))
		if wait, _ := strconv.Atoi(q.Get("wait")); wait > 0 && since > 0 {
			if wait > 55 {
				wait = 55
			}
			db.WaitForChange(since, time.Duration(wait)*time.Second, r.Context().Done())
		}
		changes, err := db.ChangesSince(since, limit)
		if err != nil {
			http.Error(w, "could not read the change log", http.StatusInternalServerError)
			return
		}
		if changes.Changed == nil {
			changes.Changed = []string{}
		}
		if changes.Removed == nil {
			changes.Removed = []string{}
		}
		writeJSON(w, changes)
	})
}
