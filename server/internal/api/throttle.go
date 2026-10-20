package api

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Throttle slows down password guessing. Sign-in had no limit at all, so a
// device on the network could try passwords as fast as it could send them
// (OWASP API2:2023). Failures are counted per address and per account name;
// past a threshold each is refused for a while, longer each time, and a
// correct password clears the count.
type Throttle struct {
	mu    sync.Mutex
	fails map[string]*strike
	now   func() time.Time
}

type strike struct {
	count int
	last  time.Time
	until time.Time
}

const (
	freeAttempts = 5                // before any lockout
	strikeWindow = 15 * time.Minute // failures older than this are forgotten
	baseLockout  = 30 * time.Second
	maxLockout   = 15 * time.Minute
)

// NewThrottle makes an empty throttle.
func NewThrottle() *Throttle {
	return &Throttle{fails: map[string]*strike{}, now: time.Now}
}

func throttleKeys(r *http.Request, user string) []string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	return []string{"ip:" + host, "user:" + strings.ToLower(strings.TrimSpace(user))}
}

// Blocked is how long the caller must wait, or zero.
func (t *Throttle) Blocked(r *http.Request, user string) time.Duration {
	t.mu.Lock()
	defer t.mu.Unlock()
	var wait time.Duration
	for _, k := range throttleKeys(r, user) {
		if s := t.fails[k]; s != nil {
			if d := s.until.Sub(t.now()); d > wait {
				wait = d
			}
		}
	}
	return wait
}

// Failed records a wrong password.
func (t *Throttle) Failed(r *http.Request, user string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	for _, k := range throttleKeys(r, user) {
		s := t.fails[k]
		if s == nil || now.Sub(s.last) > strikeWindow {
			s = &strike{}
			t.fails[k] = s
		}
		s.count++
		s.last = now
		if s.count > freeAttempts {
			lock := baseLockout << uint(min(s.count-freeAttempts-1, 5))
			if lock > maxLockout {
				lock = maxLockout
			}
			s.until = now.Add(lock)
		}
	}
}

// Succeeded clears the count for this address and account.
func (t *Throttle) Succeeded(r *http.Request, user string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	for _, k := range throttleKeys(r, user) {
		delete(t.fails, k)
	}
}

// refuseThrottled answers 429 with a Retry-After, and reports true.
func refuseThrottled(w http.ResponseWriter, wait time.Duration) bool {
	if wait <= 0 {
		return false
	}
	secs := int(wait.Seconds()) + 1
	w.Header().Set("Retry-After", itoa(secs))
	writeJSON(w, http.StatusTooManyRequests, errorBody{"too many wrong passwords; try again in " + itoa(secs) + " seconds"})
	return true
}

// minPasswordLength is for passwords set here. One imported from Jellyfin
// keeps working whatever its length; the next change has to meet this.
const minPasswordLength = 8
