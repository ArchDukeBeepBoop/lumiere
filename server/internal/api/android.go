package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// The Android app's two ways home: what it was doing, and a newer copy of
// itself. A projector that cannot be reached over USB has no other way to
// say what went wrong, or to be updated, than through the server it already
// talks to.
type AndroidHandler struct {
	DataDir string
	Log     *slog.Logger
}

func (h AndroidHandler) dir() string { return filepath.Join(h.DataDir, "android") }

// Diagnostics is POST /Lumiere/Diagnostics: the app's recent log, written to
// this server's log under the device's name. Capped, and only ever written,
// never served back.
func (h AndroidHandler) Diagnostics(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 256<<10))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"too large"})
		return
	}
	device := CredentialsFrom(r.Header).Device
	for _, line := range strings.Split(string(body), "\n") {
		if strings.TrimSpace(line) != "" {
			h.Log.Info("android", "device", device, "log", line)
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

// Latest is GET /Lumiere/Android/Latest: {"VersionCode", "VersionName"} of
// the copy waiting in <data>/android, or 404 when none is.
func (h AndroidHandler) Latest(w http.ResponseWriter, r *http.Request) {
	raw, err := os.ReadFile(filepath.Join(h.dir(), "version.json"))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	var v map[string]any
	if json.Unmarshal(raw, &v) != nil {
		http.NotFound(w, r)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// Package is GET /Lumiere/Android/lumiere.apk: the copy itself.
func (h AndroidHandler) Package(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	http.ServeFile(w, r, filepath.Join(h.dir(), "lumiere.apk"))
}
