package api

import (
	"net/http"
	"testing"
)

// The sign-in header is the first thing parsed from any device, before it
// has proved anything. Whatever arrives, the parser returns — no panic.
func FuzzCredentialsHeader(f *testing.F) {
	for _, seed := range []string{
		`MediaBrowser Client="Lumiere", Device="Mac", DeviceId="x", Version="1", Token="abc"`,
		`MediaBrowser Token=""`, `Bearer abc`, `"`, `MediaBrowser ,,,=,"`, "",
	} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, raw string) {
		h := http.Header{}
		h.Set("Authorization", raw)
		h.Set("X-Emby-Authorization", raw)
		_ = CredentialsFrom(h)
	})
}
