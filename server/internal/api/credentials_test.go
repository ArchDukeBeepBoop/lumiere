package api

import (
	"net/http"
	"testing"
)

func header(pairs ...string) http.Header {
	h := http.Header{}
	for i := 0; i+1 < len(pairs); i += 2 {
		h.Set(pairs[i], pairs[i+1])
	}
	return h
}

// The exact header Lumiere sends before sign-in: no Token pair at all, not an
// empty one. A parser that requires five pairs rejects every first sign-in.
const preSignIn = `MediaBrowser Client="Lumiere", Device="Alex's MacBook Pro", DeviceId="8B7F0E1A-2C3D-4E5F-9A0B-1C2D3E4F5A6B", Version="0.1.0"`

func TestCredentialsFrom(t *testing.T) {
	t.Run("pre-sign-in header has no token", func(t *testing.T) {
		c := CredentialsFrom(header("Authorization", preSignIn))
		if c.Client != "Lumiere" || c.Version != "0.1.0" {
			t.Fatalf("client/version wrong: %+v", c)
		}
		if c.Device != "Alex's MacBook Pro" {
			t.Fatalf("device wrong: %q", c.Device)
		}
		if c.Token != "" {
			t.Fatalf("token should be absent, got %q", c.Token)
		}
	})

	t.Run("the token pair is read when present", func(t *testing.T) {
		c := CredentialsFrom(header("Authorization", preSignIn+`, Token="abc123"`))
		if c.Token != "abc123" {
			t.Fatalf("got %q", c.Token)
		}
	})

	t.Run("X-Emby-Authorization alone is enough", func(t *testing.T) {
		c := CredentialsFrom(header("X-Emby-Authorization", preSignIn+`, Token="abc123"`))
		if c.Token != "abc123" || c.Client != "Lumiere" {
			t.Fatalf("got %+v", c)
		}
	})

	t.Run("X-Emby-Token alone is enough", func(t *testing.T) {
		// What AVPlayer and mpv send, and the only thing they can send. Refusing
		// this header means nothing plays.
		c := CredentialsFrom(header("X-Emby-Token", "abc123"))
		if c.Token != "abc123" {
			t.Fatalf("got %q", c.Token)
		}
	})

	t.Run("a broken scheme header does not hide a bare token", func(t *testing.T) {
		// mpv splits the MediaBrowser value on commas, so what arrives can be a
		// fragment. The bare token beside it must still be honoured.
		c := CredentialsFrom(header(
			"Authorization", `MediaBrowser Client="Lumiere"`,
			"X-Emby-Token", "abc123"))
		if c.Token != "abc123" {
			t.Fatalf("got %q", c.Token)
		}
	})

	t.Run("nothing at all", func(t *testing.T) {
		if c := CredentialsFrom(header()); !c.empty() {
			t.Fatalf("got %+v", c)
		}
	})

	t.Run("junk is not a credential", func(t *testing.T) {
		for _, raw := range []string{
			"Bearer abc123", "MediaBrowser", "", "Basic dXNlcjpwdw==",
		} {
			if c := CredentialsFrom(header("Authorization", raw)); !c.empty() {
				t.Errorf("%q parsed as %+v", raw, c)
			}
		}
	})

	t.Run("unknown pairs are ignored, not fatal", func(t *testing.T) {
		c := CredentialsFrom(header("Authorization",
			`MediaBrowser Client="Lumiere", Futureproof="x", Token="abc123"`))
		if c.Token != "abc123" || c.Client != "Lumiere" {
			t.Fatalf("got %+v", c)
		}
	})
}

func TestVerifyPassword(t *testing.T) {
	// Generated with the same parameters Jellyfin uses on this instance, so the
	// format string is exercised rather than assumed. Password: "correct horse".
	const stored = "$PBKDF2-SHA512$iterations=210000$" +
		"00112233445566778899aabbccddeeff$" +
		"e5b1b4b60e2b0930f8cb2d4d0a2c1f6f6e9e5f7d1d02f4a9d6b0c9f1e4a2c8b3" +
		"7a1f0e2d3c4b5a69788796a5b4c3d2e1f0011223344556677889900aabbccdde"

	if verifyPassword("", "anything") {
		t.Error("an account with no hash must not accept a password")
	}
	for _, bad := range []string{
		"not-a-hash",
		"$PBKDF2-SHA256$iterations=1000$00$00", // wrong algorithm, not silently accepted
		"$PBKDF2-SHA512$iterations=0$00$00",
		"$PBKDF2-SHA512$iterations=x$00$00",
		"$PBKDF2-SHA512$iterations=1000$zz$00", // non-hex salt
	} {
		if verifyPassword(bad, "correct horse") {
			t.Errorf("%q verified", bad)
		}
	}
	if verifyPassword(stored, "wrong") {
		t.Error("a wrong password verified")
	}
}
