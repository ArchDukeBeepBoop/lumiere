package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Network serves the library to the home network when asked — the Android
// app's way in. Off unless turned on in Settings.
//
// The loopback bind stays exactly as it was; this adds a second listener on
// each of the Mac's private addresses, never 0.0.0.0. It answers only peers
// that are themselves on a private network, and only under the address it was
// reached on, so the DNS-rebinding guard in LocalOnly still holds. Every route
// past sign-in still needs a token. And it answers Jellyfin's discovery
// broadcast on UDP 7359, so the phone can find the server without an address
// typed in.
type Network struct {
	Handler  http.Handler
	Port     int
	Identity Identity
	Log      *slog.Logger

	mu        sync.Mutex
	servers   []*http.Server
	discovery net.PacketConn
}

// NetworkOnChange is set at start: Settings calls it when the switch moves.
var NetworkOnChange func(on bool)

// Addresses are this Mac's private IPv4 addresses on Wi-Fi or Ethernet, the
// ones a phone or TV in the house can reach. A VPN's tunnel has a private
// address too (10.2.0.2 here) and everyone else on that VPN shares its
// network; it is left out, as are Internet Sharing's bridge and Apple's
// peer-to-peer links.
func Addresses() []string {
	var out []string
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if !homeInterface(iface.Name, iface.Flags, len(iface.HardwareAddr)) {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			if n, ok := a.(*net.IPNet); ok && n.IP.To4() != nil && n.IP.IsPrivate() {
				out = append(out, n.IP.String())
			}
		}
	}
	return out
}

// Apply starts or stops the network listeners to match the switch.
func (n *Network) Apply(on bool) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.stop()
	if !on {
		return
	}
	for _, ip := range Addresses() {
		addr := net.JoinHostPort(ip, fmt.Sprint(n.Port))
		listener, err := net.Listen("tcp", addr)
		if err != nil {
			n.Log.Info("network: cannot listen", "addr", addr, "error", err)
			continue
		}
		server := &http.Server{
			Handler:           notBlocked(sameNetworkOnly(ip, privatePeersOnly(LocalOnly(addr, n.Handler)))),
			ReadHeaderTimeout: 10 * time.Second,
			IdleTimeout:       120 * time.Second,
		}
		n.servers = append(n.servers, server)
		go server.Serve(listener)
		n.Log.Info("network: listening", "addr", addr)
	}
	if conn, err := net.ListenPacket("udp4", ":7359"); err == nil {
		n.discovery = conn
		go n.answerDiscovery(conn)
	} else {
		n.Log.Info("network: discovery unavailable", "error", err)
	}
}

func (n *Network) stop() {
	for _, s := range n.servers {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		s.Shutdown(ctx)
		cancel()
	}
	n.servers = nil
	if n.discovery != nil {
		n.discovery.Close()
		n.discovery = nil
	}
}

// answerDiscovery is Jellyfin's protocol: "who is JellyfinServer?" in, the
// server's address, id and name out, to the asker only.
func (n *Network) answerDiscovery(conn net.PacketConn) {
	buf := make([]byte, 512)
	for {
		size, from, err := conn.ReadFrom(buf)
		if err != nil {
			return
		}
		udp, ok := from.(*net.UDPAddr)
		if !ok || !udp.IP.IsPrivate() ||
			!strings.Contains(strings.ToLower(string(buf[:size])), "who is jellyfinserver") {
			continue
		}
		address := ""
		for _, ip := range Addresses() {
			if sameSubnet(ip, udp.IP) {
				address = fmt.Sprintf("http://%s:%d", ip, n.Port)
			}
		}
		if address == "" {
			continue
		}
		reply, _ := json.Marshal(map[string]string{
			"Address": address, "Id": n.Identity.ServerID, "Name": n.Identity.ServerName,
		})
		conn.WriteTo(reply, from)
	}
}

func sameSubnet(local string, peer net.IP) bool {
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			if n, ok := a.(*net.IPNet); ok && n.IP.String() == local && n.Contains(peer) {
				return true
			}
		}
	}
	return false
}

// privatePeersOnly refuses anyone not on a private network — a router that
// forwards the port by mistake must not make the library public.
func privatePeersOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		if ip := net.ParseIP(host); ip == nil || !(ip.IsPrivate() || ip.IsLoopback()) {
			http.Error(w, "home network only", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// homeInterface is a physical Wi-Fi or Ethernet link: up, able to broadcast,
// with a hardware address, and not one of macOS's virtual ones. Pure, so the
// rule is tested by name.
func homeInterface(name string, flags net.Flags, hardwareLen int) bool {
	if flags&net.FlagUp == 0 || flags&net.FlagLoopback != 0 ||
		flags&net.FlagPointToPoint != 0 || flags&net.FlagBroadcast == 0 || hardwareLen == 0 {
		return false
	}
	for _, virtual := range []string{"utun", "ipsec", "ppp", "gif", "stf", "bridge", "awdl", "llw", "anpi", "ap", "vmenet", "vnic"} {
		if strings.HasPrefix(name, virtual) {
			return false
		}
	}
	return true
}

// sameNetworkOnly answers only peers on the listening address's own network:
// a phone on the Wi-Fi, not something routed in from elsewhere.
func sameNetworkOnly(local string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		if ip := net.ParseIP(host); ip == nil || !(ip.IsLoopback() || sameSubnet(local, ip)) {
			http.Error(w, "home network only", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Blocked is set at start: whether an address is on Settings' blocked list.
var Blocked = func(ip string) bool { return false }

// notBlocked refuses a blocked device before anything else, sign-in included.
func notBlocked(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		if Blocked(host) {
			http.Error(w, "this device is blocked", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// WakeAddress is the hardware address of the first shared interface — what a
// wake-on-LAN packet is addressed to. Only over a signed-in route.
func WakeAddress() string {
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if homeInterface(iface.Name, iface.Flags, len(iface.HardwareAddr)) {
			return iface.HardwareAddr.String()
		}
	}
	return ""
}
