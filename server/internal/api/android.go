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

// channels are the apps besides the TV's, each with its own copy in
// <data>/android/<channel>, so a phone is never offered the TV's app. The TV
// keeps the folder's top level, where it has always looked. Named here, not
// taken from the path as given, so a request can only ever reach these.
var channels = map[string]bool{"phone": true, "quest": true}

// folder is where the asked-for app's copy waits, or "" for a channel that
// does not exist.
func (h AndroidHandler) folder(r *http.Request) string {
	channel := r.PathValue("channel")
	if channel == "" {
		return h.dir()
	}
	if !channels[channel] {
		return ""
	}
	return filepath.Join(h.dir(), channel)
}

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

// Latest is GET /Lumiere/Android/Latest (the TV's) or
// /Lumiere/Android/{channel}/Latest (the phone's, the Quest's):
// {"VersionCode", "VersionName", "Sha256"} of the copy waiting, or 404.
func (h AndroidHandler) Latest(w http.ResponseWriter, r *http.Request) {
	dir := h.folder(r)
	if dir == "" {
		http.NotFound(w, r)
		return
	}
	raw, err := os.ReadFile(filepath.Join(dir, "version.json"))
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

// Package is GET /Lumiere/Android/lumiere.apk, or …/{channel}/lumiere.apk:
// the copy itself.
func (h AndroidHandler) Package(w http.ResponseWriter, r *http.Request) {
	dir := h.folder(r)
	if dir == "" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	http.ServeFile(w, r, filepath.Join(dir, "lumiere.apk"))
}
