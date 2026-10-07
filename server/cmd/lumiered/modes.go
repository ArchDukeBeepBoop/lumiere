package main

import (
	"log/slog"
	"net/http"
	"time"
)

// The other modes of the binary and the request log. Split from main.go for
// the 300-line rule.

// logging records one line per request: method, path, status, duration.
//
// Every request but the liveness poll; see how four range requests make one playback.
func logging(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		// LumiereControl's liveness poll, every five seconds, is not worth a line.
		if r.URL.Path == "/System/Info/Public" && rec.status == http.StatusOK {
			return
		}
		log.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"ms", time.Since(started).Milliseconds(),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}
