package api

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"testing"
	"time"
)

func TestSameAddressesIgnoresOrder(t *testing.T) {
	if !sameAddresses([]string{"192.168.2.40", "10.0.0.5"}, []string{"10.0.0.5", "192.168.2.40"}) {
		t.Fatal("same addresses in another order should match")
	}
	if sameAddresses(nil, []string{"192.168.2.40"}) || sameAddresses([]string{"192.168.2.39"}, []string{"192.168.2.40"}) {
		t.Fatal("different addresses should not match")
	}
}

// The server starts with no address (Wi-Fi not joined yet), then gets one:
// the listener follows within a tick, where before it never came.
func TestWatchFollowsANewAddress(t *testing.T) {
	var mu sync.Mutex
	current := []string{}
	n := &Network{
		Handler: http.NotFoundHandler(), Port: 0,
		Log:       slog.New(slog.NewTextHandler(io.Discard, nil)),
		addresses: func() []string { mu.Lock(); defer mu.Unlock(); return current },
	}
	n.Apply(true)
	defer n.Apply(false)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go n.Watch(ctx, 10*time.Millisecond)

	mu.Lock()
	current = []string{"127.0.0.1"}
	mu.Unlock()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		n.mu.Lock()
		got := sameAddresses(n.listening, []string{"127.0.0.1"}) && len(n.servers) == 1
		n.mu.Unlock()
		if got {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("the listener never moved to the new address")
}

// Switched off, it stays off whatever the addresses do.
func TestWatchLeavesSharingOff(t *testing.T) {
	n := &Network{Handler: http.NotFoundHandler(), Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
		addresses: func() []string { return []string{"127.0.0.1"} }}
	n.Apply(false)
	ctx, cancel := context.WithCancel(context.Background())
	go n.Watch(ctx, 5*time.Millisecond)
	time.Sleep(50 * time.Millisecond)
	cancel()
	n.mu.Lock()
	defer n.mu.Unlock()
	if len(n.servers) != 0 {
		t.Fatal("sharing is off; nothing should listen")
	}
}
