package metadata

import (
	"os"
	"path/filepath"
	"testing"
)

func TestTokenRoundTrip(t *testing.T) {
	dir := t.TempDir()
	if got := ReadToken(dir); got != "" {
		t.Errorf("a server with no key should read empty, got %q", got)
	}

	if err := WriteToken(dir, "  secret-token\n"); err != nil {
		t.Fatal(err)
	}
	if got := ReadToken(dir); got != "secret-token" {
		t.Errorf("ReadToken = %q, want the trimmed token", got)
	}

	// A third-party credential is the user's property and gets the session
	// token's handling.
	info, err := os.Stat(filepath.Join(dir, tokenFile))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v, want 0600", info.Mode().Perm())
	}

	// Clearing is a real request, not an empty string to store.
	if err := WriteToken(dir, ""); err != nil {
		t.Fatal(err)
	}
	if got := ReadToken(dir); got != "" {
		t.Errorf("after clearing, ReadToken = %q", got)
	}
	// And clearing twice is not an error.
	if err := WriteToken(dir, ""); err != nil {
		t.Errorf("clearing an absent key: %v", err)
	}
}
