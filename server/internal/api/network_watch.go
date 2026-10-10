package api

import (
	"context"
	"slices"
	"time"
)

// Watch keeps the network listeners on the Mac's addresses as they change.
// The server often starts at login before Wi-Fi has joined, and a Mac's
// address can change when it wakes or the router hands out another; the
// listeners were bound once, so the library vanished from the phone and TV
// while the Mac itself still reached it. Every [every], while sharing is on,
// the addresses are looked at again and the listeners moved if they differ.
func (n *Network) Watch(ctx context.Context, every time.Duration) {
	tick := time.NewTicker(every)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			n.mu.Lock()
			on, have, look := n.on, n.listening, n.addresses
			n.mu.Unlock()
			if !on || look == nil {
				continue
			}
			if now := look(); !sameAddresses(have, now) {
				n.Log.Info("network: addresses changed", "from", have, "to", now)
				n.Apply(true)
			}
		}
	}
}

// sameAddresses compares two address lists, whatever their order.
func sameAddresses(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	a, b = slices.Clone(a), slices.Clone(b)
	slices.Sort(a)
	slices.Sort(b)
	return slices.Equal(a, b)
}
