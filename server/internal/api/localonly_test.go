package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestLocalOnly(t *testing.T) {
	handler := LocalOnly("127.0.0.1:8098", http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusTeapot) }))

	cases := []struct {
		name   string
		host   string
		origin string
		want   int
	}{
		{"the client's own request", "127.0.0.1:8098", "", http.StatusTeapot},
		{"localhost by name", "localhost:8098", "", http.StatusTeapot},
		{"IPv6 loopback", "[::1]:8098", "", http.StatusTeapot},
		{"a rebound DNS name", "evil.example.com", "", http.StatusForbidden},
		{"a rebound name with the right port", "evil.example.com:8098", "", http.StatusForbidden},
		{"a browser fetch from a web page", "127.0.0.1:8098", "https://evil.example.com", http.StatusForbidden},
		{"a local page, which is not the threat", "127.0.0.1:8098", "http://localhost:3000", http.StatusTeapot},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://x/System/Info/Public", nil)
			r.Host = c.host
			if c.origin != "" {
				r.Header.Set("Origin", c.origin)
			}
			w := httptest.NewRecorder()
			handler.ServeHTTP(w, r)
			if w.Code != c.want {
				t.Errorf("status = %d, want %d", w.Code, c.want)
			}
		})
	}
}
