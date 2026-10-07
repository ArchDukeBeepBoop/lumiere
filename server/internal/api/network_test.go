package api

import (
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestOnlyPrivatePeersAreServed(t *testing.T) {
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})
	h := privatePeersOnly(ok)
	for peer, want := range map[string]int{
		"192.168.60.20:5000": 200, "10.0.0.4:1": 200, "127.0.0.1:1": 200,
		"8.8.8.8:53": 403, "100.64.0.1:1": 403,
	} {
		r := httptest.NewRequest("GET", "/System/Info/Public", nil)
		r.RemoteAddr = peer
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != want {
			t.Errorf("%s: got %d, want %d", peer, w.Code, want)
		}
	}
}

func TestOnlyWiFiAndEthernetAreShared(t *testing.T) {
	up := net.FlagUp | net.FlagBroadcast | net.FlagMulticast
	cases := []struct {
		name  string
		flags net.Flags
		hw    int
		want  bool
	}{
		{"en0", up, 6, true},
		{"en7", up, 6, true},
		{"utun4", net.FlagUp | net.FlagPointToPoint, 0, false}, // a VPN
		{"bridge100", up, 6, false},                            // Internet Sharing
		{"awdl0", up, 6, false},
		{"en1", net.FlagBroadcast, 6, false}, // down
	}
	for _, c := range cases {
		if got := homeInterface(c.name, c.flags, c.hw); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestABlockedDeviceIsRefusedBeforeSignIn(t *testing.T) {
	old := Blocked
	defer func() { Blocked = old }()
	Blocked = func(ip string) bool { return ip == "192.168.50.19" }
	h := notBlocked(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	for peer, want := range map[string]int{"192.168.50.19:4000": 403, "192.168.50.28:4000": 200} {
		r := httptest.NewRequest("GET", "/System/Info/Public", nil)
		r.RemoteAddr = peer
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != want {
			t.Errorf("%s: got %d, want %d", peer, w.Code, want)
		}
	}
}
