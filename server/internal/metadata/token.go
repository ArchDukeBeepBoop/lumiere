package metadata

import (
	"os"
	"path/filepath"
	"strings"
)

// tokenFile is where the provider key lives, beside the database.
const tokenFile = "tmdb.token"

// ReadToken returns the provider key, or empty where there is none.
//
// A file rather than an environment variable, because this server is launched
// by a menu-bar app: LumiereControl passes it almost no environment, so a key
// set in a shell profile would be present when tested from a terminal and
// absent in the way the thing actually runs.
//
// Empty is not an error. Every part of this package is optional — a library
// with no key is a library that keeps the names its files gave it.
func ReadToken(dataDir string) string {
	body, err := os.ReadFile(filepath.Join(dataDir, tokenFile))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(body))
}

// WriteToken stores the key.
//
// 0600, and the directory is already 0700: a third-party credential is the
// user's property and gets the handling the session token gets.
func WriteToken(dataDir, token string) error {
	path := filepath.Join(dataDir, tokenFile)
	if strings.TrimSpace(token) == "" {
		// Clearing is a real request, and an empty file that reads back as "no
		// key" would be a key nobody can remove.
		err := os.Remove(path)
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	return os.WriteFile(path, []byte(strings.TrimSpace(token)+"\n"), 0o600)
}
