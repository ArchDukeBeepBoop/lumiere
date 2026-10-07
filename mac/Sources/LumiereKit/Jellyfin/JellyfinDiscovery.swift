import Foundation
import Darwin

/// A server that answered the discovery broadcast.
/// Declared here rather than beside the auth types: an identical struct sat unused
/// in JellyfinAuth.swift from phase 1, left behind when discovery itself was never
/// written. It lives with the code that produces it now.
public struct DiscoveredServer: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let address: URL

    public init(id: String, name: String, address: URL) {
        self.id = id
        self.name = name
        self.address = address
    }

    public var displayAddress: String {
        guard let host = address.host else { return address.absoluteString }
        if let port = address.port { return "\(host):\(port)" }
        return host
    }
}

/// Finds Jellyfin servers on the local network.
///
/// Jellyfin listens for the UDP string "who is JellyfinServer?" on port 7359 and
/// replies with its own address, name and id. This was in the plan from phase 1 and
/// never got built, and its absence is the whole reason signing in was hard: the
/// only clue on the screen was a placeholder address, and a placeholder is a guess
/// about someone else's network. Typing a wrong subnet returns "couldn't reach the
/// server", which is true and completely unhelpful.
///
/// BSD sockets rather than Network.framework: this needs a single broadcast
/// datagram and a short listen, and `NWConnection` has no clean broadcast story.
public enum JellyfinDiscovery {

    public static let port: UInt16 = 7359
    private static let probe = "who is JellyfinServer?"

    private struct Payload: Decodable {
        let address: String?
        let id: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case address = "Address"
            case id = "Id"
            case name = "Name"
        }
    }

    /// Broadcasts, then collects replies until `timeout` elapses.
    ///
    /// Off the main actor: it is a blocking socket loop, and running it inline would
    /// freeze the sign-in window for the whole listen window.
    public static func discover(timeout: TimeInterval = 2.5) async -> [DiscoveredServer] {
        await Task.detached(priority: .userInitiated) {
            collect(timeout: timeout)
        }.value
    }

    private static func collect(timeout: TimeInterval) -> [DiscoveredServer] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        // A quarter-second receive timeout, so the loop can re-check the overall
        // deadline instead of blocking past it.
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let message = Array(probe.utf8)
        for target in broadcastAddresses() {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = target
            withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = message.withUnsafeBytes { bytes in
                        sendto(fd, bytes.baseAddress, bytes.count, 0,
                               sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var found: [String: DiscoveredServer] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 2048)

        while Date() < deadline {
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received: Int = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    buffer.withUnsafeMutableBytes { bytes in
                        recvfrom(fd, bytes.baseAddress, bytes.count, 0, sa, &fromLength)
                    }
                }
            }
            guard received > 0 else { continue }

            let data = Data(buffer[0..<received])
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  let id = payload.id, !id.isEmpty
            else { continue }

            // Prefer the address the server reports. It knows which interface it is
            // actually reachable on; the packet's source address may be a different
            // one on a multi-homed box.
            let reported = payload.address.flatMap { URL(string: $0) }
            let fallback = URL(string: "http://\(ipString(from.sin_addr))\(":8096")")
            guard let url = reported ?? fallback else { continue }

            found[id] = DiscoveredServer(
                id: id,
                name: payload.name ?? url.host ?? "Lumiere",
                address: url
            )
        }

        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every interface's broadcast address, plus the global one.
    ///
    /// 255.255.255.255 alone is not enough — it is routed inconsistently, and a
    /// probe that only used it found nothing on this very machine while a
    /// per-interface broadcast answered immediately.
    private static func broadcastAddresses() -> [in_addr_t] {
        var addresses: [in_addr_t] = [INADDR_BROADCAST]

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return addresses }
        defer { freeifaddrs(head) }

        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_BROADCAST != 0,
                  flags & IFF_LOOPBACK == 0,
                  let broadcast = interface.pointee.ifa_dstaddr,
                  broadcast.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            let value = broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            if value != 0, !addresses.contains(value) {
                addresses.append(value)
            }
        }
        return addresses
    }

    private static func ipString(_ addr: in_addr) -> String {
        var value = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN))
        // Truncated at the terminator ourselves. `String(cString:)` is deprecated,
        // and the replacement does not stop at the NUL — handing it the whole
        // 16-byte buffer yields an address followed by a run of zero characters.
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
