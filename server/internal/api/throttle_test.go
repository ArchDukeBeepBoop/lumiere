package api

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestPasswordGuessingIsSlowedAndAnswerClearsIt(t *testing.T) {
	th := NewThrottle()
	clock := time.Unix(1_000_000, 0)
	th.now = func() time.Time { return clock }
	r := httptest.NewRequest("POST", "/", nil)
	r.RemoteAddr = "192.168.50.9:4000"
	for i := 0; i < freeAttempts; i++ {
		if th.Blocked(r, "me") > 0 {
			t.Fatalf("blocked after only %d tries", i)
		}
		th.Failed(r, "me")
	}
	th.Failed(r, "me")
	if th.Blocked(r, "me") <= 0 {
		t.Fatal("not blocked after the free attempts")
	}
	// Another address guessing the same account is blocked too.
	other := httptest.NewRequest("POST", "/", nil)
	other.RemoteAddr = "192.168.50.10:4000"
	if th.Blocked(other, "ME") <= 0 {
		t.Fatal("the account itself was not protected")
	}
	clock = clock.Add(maxLockout + time.Second)
	if th.Blocked(r, "me") > 0 {
		t.Fatal("still blocked after the lockout")
	}
	th.Succeeded(r, "me")
	th.Failed(r, "me")
	if th.Blocked(r, "me") > 0 {
		t.Fatal("a correct password did not clear the count")
	}
}
