import ControlCore
import Darwin
import Foundation

/// Keeps the menu's picture of the library current.
///
/// Refreshed on a slow beat and whenever the menu opens. The read happens off
/// the main thread — counting 50,000 rows is milliseconds, but milliseconds on
/// the main thread are the ones you feel when a menu opens.
@MainActor
@Observable
final class LibraryMonitor {
    private(set) var stats: LibraryStats?
    /// This Mac's address on the home network, for the Sharing row.
    private(set) var lanAddress: String?

    static let database = BackupRestorer.dataDir.appendingPathComponent("library.db")
    static let logFile = BackupRestorer.dataDir.appendingPathComponent("logs/lumiered.log")

    func refresh() async {
        let url = Self.database
        let fresh = await Task.detached(priority: .utility) {
            LibraryStats.read(database: url)
        }.value
        // Assigned only when it changed, so an open menu is not redrawn every
        // beat for numbers that did not move.
        if fresh != stats { stats = fresh }
        let address = Self.homeAddress()
        if address != lanAddress { lanAddress = address }
    }

    /// The first IPv4 address on Wi-Fi or Ethernet.
    ///
    /// Read from the interfaces, never by connecting anywhere: no packet leaves
    /// the machine, so macOS has no Local Network prompt to show. VPN tunnels
    /// (utun) are skipped on purpose — the server shares on the home network
    /// only, and an address on a tunnel is not where a television would look.
    static func homeAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var found: [String: String] = [:]
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            found[name] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                                 as: UTF8.self)
        }
        // en0 first: on a Mac that is the built-in port, Wi-Fi or Ethernet.
        return found["en0"] ?? found.keys.sorted().first.flatMap { found[$0] }
    }
}
