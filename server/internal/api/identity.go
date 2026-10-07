package api

import (
	"os"
	"path/filepath"
)

// ResolveIdentity decides what this server calls itself, and in particular what
// ServerId it reports.
//
// That id is not cosmetic. Lumiere stores it with the session and keys its local
// cache on it — 45,000 items and, more importantly, the watch state written
// while the server was away. Reporting one id rather than another decides
// whether the client treats this as the server it already knows or as a stranger.
//
// The id is this server's own, minted once and kept in the data directory.
func ResolveIdentity(dataDir, listenAddr string) (Identity, error) {
	serverID, err := newServerID(dataDir)
	if err != nil {
		return Identity{}, err
	}
	return Identity{
		ServerID:     serverID,
		ServerName:   "Lumiere Server",
		Version:      "10.11.11",
		LocalAddress: "http://" + listenAddr,
	}, nil
}

// newServerID mints a fresh identifier in Jellyfin's shape: 32 lowercase hex
// characters, which is what every id in this API looks like.
//
// Persisted on first use, because an id that changes between restarts would make
// the client treat every launch as a new server.
func newServerID(dataDir string) (string, error) {
	path := filepath.Join(dataDir, "server-id")
	if existing, err := os.ReadFile(path); err == nil && len(existing) == 32 {
		return string(existing), nil
	}
	id, err := randomHex32()
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return "", err
	}
	return id, os.WriteFile(path, []byte(id), 0o644)
}
