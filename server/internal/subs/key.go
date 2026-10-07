package subs

import (
	"os"
	"path/filepath"
	"strings"
)

// keyFile is where the subtitle provider key lives, beside the database and
// the naming pass's key. Same reasoning as that one: this server is launched
// by a menu-bar app with almost no environment, so a key in a shell profile
// would work when tested from a terminal and be absent in the way the thing
// actually runs.
const keyFile = "opensubtitles.token"

// ReadKey returns the provider key, or empty where there is none. Empty is
// not an error: a server without one simply offers no subtitle search.
func ReadKey(dataDir string) string {
	body, err := os.ReadFile(filepath.Join(dataDir, keyFile))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(body))
}

// WriteKey stores the key, 0600 in a 0700 directory: a third-party
// credential gets the handling the session token gets. An empty key clears
// it, because a key nobody can remove is worse than none.
func WriteKey(dataDir, key string) error {
	path := filepath.Join(dataDir, keyFile)
	if strings.TrimSpace(key) == "" {
		err := os.Remove(path)
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	return os.WriteFile(path, []byte(strings.TrimSpace(key)+"\n"), 0o600)
}
