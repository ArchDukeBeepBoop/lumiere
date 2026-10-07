import Foundation

/// Turns whatever a person types into an ordered list of URLs worth trying.
///
/// People type `192.168.60.40`, `jellyfin.local:8096`, `https://media.example.com`,
/// or paste `http://192.168.60.40:8096/web/index.html#!/home.html` straight out of a
/// browser. All of those should work. Pure and fully unit-tested — no networking
/// happens here, it only proposes candidates for `JellyfinSignIn` to probe in order.
public enum ServerURLNormalizer {

    /// Jellyfin's default HTTP port. Tried as a fallback when the input has no port,
    /// since a bare LAN IP almost always means a stock install.
    public static let defaultPort = 8096

    public static func candidates(from input: String) -> [URL] {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        // Strip anything after the host/port that belongs to the web UI rather than
        // the API root: paths, the SPA fragment, query strings.
        raw = stripWebUIPath(raw)
        guard !raw.isEmpty else { return [] }

        let hasScheme = raw.contains("://")
        let schemes: [String]
        var hostPart = raw

        if hasScheme {
            let parts = raw.components(separatedBy: "://")
            guard parts.count >= 2, !parts[1].isEmpty else { return [] }
            schemes = [parts[0].lowercased()]
            hostPart = parts[1]
        } else {
            // No scheme: prefer http, because a server typed as a bare address is
            // nearly always a LAN box without a certificate.
            schemes = ["http", "https"]
        }

        guard isPlausibleHost(hostPart) else { return [] }

        let hasPort = portIsSpecified(in: hostPart)

        var result: [URL] = []
        for scheme in schemes {
            if let url = URL(string: "\(scheme)://\(hostPart)") {
                result.append(url)
            }
            // Only worth trying the default port when none was given, and only for
            // http — a stock Jellyfin does not serve 8096 over TLS.
            if !hasPort, scheme == "http",
               let url = URL(string: "http://\(hostPart):\(defaultPort)") {
                result.append(url)
            }
        }
        return result
    }

    /// Removes the path, query and fragment, keeping only `host[:port]`.
    private static func stripWebUIPath(_ input: String) -> String {
        var value = input

        let schemeSeparator = "://"
        var scheme = ""
        if let range = value.range(of: schemeSeparator) {
            scheme = String(value[..<range.upperBound])
            value = String(value[range.upperBound...])
        }

        for terminator in ["/", "?", "#"] {
            if let index = value.firstIndex(of: Character(terminator)) {
                value = String(value[..<index])
            }
        }
        return scheme + value
    }

    /// True when `host` carries an explicit `:port`. Careful with IPv6 literals,
    /// where the colons are part of the address rather than a port separator.
    private static func portIsSpecified(in host: String) -> Bool {
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { return false }
            return host[close...].contains(":")
        }
        guard let colon = host.lastIndex(of: ":") else { return false }
        let suffix = host[host.index(after: colon)...]
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    private static func isPlausibleHost(_ host: String) -> Bool {
        guard !host.isEmpty, !host.hasPrefix(":"), !host.hasPrefix("."), !host.contains(" ") else {
            return false
        }
        // An empty or non-numeric port is a typo, not something to probe.
        if host.hasPrefix("[") { return host.contains("]") }
        if let colon = host.lastIndex(of: ":") {
            let suffix = host[host.index(after: colon)...]
            if suffix.isEmpty { return false }
            if !suffix.allSatisfy(\.isNumber) { return false }
            if let port = Int(suffix), port < 1 || port > 65535 { return false }
            let hostname = host[..<colon]
            return !hostname.isEmpty
        }
        return true
    }
}
