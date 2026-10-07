package api

import (
	"testing"
)

// The one place this server makes an outbound request to a URL that arrived in a
// request body. Everything outside the allowlist must be refused before the
// fetch, not after.
func TestPosterHostsAreRestricted(t *testing.T) {
	cases := []struct {
		url  string
		want bool // true = refused
	}{
		{"https://image.tmdb.org/t/p/w342/abc.jpg", false},
		{"https://artworks.thetvdb.com/banners/posters/1.jpg", false},
		{"http://image.tmdb.org/t/p/w342/abc.jpg", true},   // plain HTTP
		{"https://evil.example.com/poster.jpg", true},      // not a provider
		{"https://127.0.0.1:8098/Items", true},             // the server itself
		{"https://169.254.169.254/latest/meta-data", true}, // cloud metadata
		{"file:///etc/passwd", true},
		{"not a url at all", true},
	}
	for _, c := range cases {
		_, err := allowedArtworkURL(c.url)
		refused := err == errUnknownArtworkHost
		if refused != c.want {
			t.Errorf("%s: refused = %v, want %v", c.url, refused, c.want)
		}
	}
}
