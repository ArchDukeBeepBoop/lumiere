// Package api implements the endpoints the Lumiere client actually calls.
// One file per group in LUMIERE_API_SPEC.md §4.
package api

import (
	"encoding/json"
	"net/http"
)

// PublicSystemInfo is GET /System/Info/Public — the first request any client
// makes, and the one that decides whether an address is a Jellyfin server at all.
//
// Field names and their exact spelling come from the spec §3.1. Lumiere reads
// four of them and requires one: a null Id makes it reject the address with
// "that answered, but it isn't a Jellyfin server", whatever else is correct.
type PublicSystemInfo struct {
	ServerName             string `json:"ServerName"`
	Version                string `json:"Version"`
	Id                     string `json:"Id"`
	LocalAddress           string `json:"LocalAddress"`
	StartupWizardCompleted bool   `json:"StartupWizardCompleted"`
	ProductName            string `json:"ProductName"`
	// Reported because Jellyfin reports it and some clients display it. It is
	// the one field here that is a fact about the machine rather than a claim.
	OperatingSystem string `json:"OperatingSystem"`
	// LumiereAPI is which of Lumiere's own routes this server has. Not in
	// Jellyfin's shape: the app compares it with what it needs, so an app
	// newer than its server says "update LumiereControl" instead of failing
	// feature by feature with generic errors.
	LumiereAPI int `json:"LumiereApi"`
}

// APILevel is bumped whenever a route the app depends on is added.
//
//	1  library health, episode orders, subtitle sync window
//	2  the subtitle queue
//	3  frames on demand, the queue by show and its retry
//	4  health findings can be ignored and restored
//	5  the last Move to Trash can be undone
//	6  misfiled episodes can be moved to their season, and moved back
const APILevel = 6

// Identity is what this server calls itself. Held rather than computed per
// request because the Id must not change between two requests — see identity.go.
type Identity struct {
	ServerID   string
	ServerName string
	// Version reported to clients. Lumiere displays it and branches on nothing,
	// but a Jellyfin-shaped version string keeps any other client's version
	// sniffing on a path it has seen before.
	Version      string
	LocalAddress string
}

// SystemHandler serves the public system info.
type SystemHandler struct {
	Identity Identity
}

func (h SystemHandler) PublicInfo(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, PublicSystemInfo{
		ServerName:             h.Identity.ServerName,
		Version:                h.Identity.Version,
		Id:                     h.Identity.ServerID,
		LocalAddress:           h.Identity.LocalAddress,
		StartupWizardCompleted: true,
		ProductName:            "Lumiere Server",
		OperatingSystem:        "Darwin",
		LumiereAPI:             APILevel,
	})
}

// writeJSON is the one place a response body is encoded, so the content type and
// the error path cannot drift between handlers.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		// The status is already sent; there is nothing to do but leave a trace.
		// Silently swallowing this is how a truncated body becomes a mystery.
		http.Error(w, "", http.StatusInternalServerError)
	}
}
