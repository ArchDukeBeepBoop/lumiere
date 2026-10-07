package api

import (
	"net"
	"net/http"
	"net/url"
	"strings"
)

// LocalOnly rejects anything that did not come from this machine's own name.
//
// The server binds 127.0.0.1, which stops packets from the network reaching it
// — and does not stop a *browser*. Two ways around a loopback bind, both well
// worn:
//
//   - **DNS rebinding.** A page on evil.com whose DNS answer flips to 127.0.0.1
//     is same-origin with whatever answers there, so the browser's origin rules
//     stop protecting anything. The connection really is local; the only thing
//     that gives it away is the `Host` header, which still says evil.com.
//   - **A cross-origin fetch.** Blocked from *reading* the reply, since nothing
//     here sends CORS headers — but the request still executes, which is enough
//     for anything with a side effect.
//
// So: the Host must name this machine, and an `Origin`, if present at all, must
// be a local one. A native client sends no Origin header ever; a browser always
// does on a cross-origin fetch. That asymmetry is the whole check.
func LocalOnly(bindAddr string, next http.Handler) http.Handler {
	allowed := map[string]bool{
		"localhost": true, "127.0.0.1": true, "::1": true, "[::1]": true, "": true,
	}
	// Whatever it was told to bind, so binding a LAN address on purpose still
	// works — the point is to refuse names this server was never given, not to
	// hardcode loopback twice.
	if host, _, err := net.SplitHostPort(bindAddr); err == nil && host != "" {
		allowed[strings.ToLower(host)] = true
	}

	isLocalHost := func(hostport string) bool {
		host := hostport
		if h, _, err := net.SplitHostPort(hostport); err == nil {
			host = h
		}
		host = strings.ToLower(strings.Trim(host, "[]"))
		if allowed[host] {
			return true
		}
		// A literal address that is loopback by any spelling — 127.0.0.2 included.
		if ip := net.ParseIP(host); ip != nil {
			return ip.IsLoopback()
		}
		return false
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !isLocalHost(r.Host) {
			http.Error(w, "not served under that name", http.StatusForbidden)
			return
		}
		if origin := r.Header.Get("Origin"); origin != "" {
			u, err := url.Parse(origin)
			if err != nil || !isLocalHost(u.Host) {
				http.Error(w, "cross-origin requests are not served", http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
