import Foundation

/// Whether the server answered the last time we asked.
///
/// Worth a type of its own because "offline" is not an error state in this app: the
/// cache is a complete local copy, so an unreachable server means browsing carries
/// on and the app only *says so*. Before this existed, a failed sync set a string
/// that nothing ever rendered — a server that was down looked, to the user,
/// exactly like a server with nothing new on it.
///
/// Lives in the kit rather than beside the UI that draws it: mapping a transport
/// failure onto something worth reading is domain logic, and keeping it here is
/// what makes it testable at all.
public enum ConnectionState: Equatable, Sendable {
    case unknown
    case online
    case offline(String)

    public var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    /// What to tell the user about a failed sync.
    ///
    /// `JellyfinError` carries a message written for a person; a raw URL error only
    /// offers `localizedDescription`. Preferring the former matters, because
    /// "connection refused" and "unauthorised" call for different actions from the
    /// user, and falling through to a generic string loses that distinction.
    public static func message(for error: Error) -> String {
        if let jellyfin = error as? JellyfinError, let described = jellyfin.errorDescription {
            return described
        }
        return error.localizedDescription
    }

    /// Whether this failure means the server could not be reached at all.
    ///
    /// The distinction the whole offline mode rests on. A server that answers 401,
    /// 500 or unparseable JSON is *up* — it just said no — and treating that as an
    /// outage would put the app into offline mode, start a reconnect probe that
    /// succeeds immediately, sync, fail the same way, and go round again. Only a
    /// transport failure counts, which in this app means `notReachable` (every
    /// URLSession error is folded into it by `JellyfinClient.execute`) plus the raw
    /// URL errors thrown by the few paths that do not go through it.
    ///
    /// Cancellation is emphatically not an outage: a sync stopped by the Stop
    /// button, or a page discarded because the user changed folder, must never flip
    /// the app offline.
    public static func isUnreachable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let jellyfin = error as? JellyfinError {
            if case .notReachable = jellyfin { return true }
            return false
        }
        if let url = error as? URLError { return unreachableURLCodes.contains(url.code) }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return unreachableURLCodes.contains(URLError.Code(rawValue: nsError.code))
    }

    /// The URL error codes that mean "nothing answered", as opposed to "something
    /// answered badly". A TLS failure is deliberately absent: a rejected certificate
    /// is a configuration problem that retrying every minute will never fix.
    private static let unreachableURLCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .networkConnectionLost,
        .timedOut,
        .internationalRoamingOff,
        .dataNotAllowed,
    ]

    /// How long to wait before the `attempt`-th reconnect probe, counting from zero.
    ///
    /// Exponential from five seconds to two minutes. The shape matters more than the
    /// numbers: this project has already shipped one loop that hammered an absent
    /// server without terminating (see the consecutive-failure comment in
    /// `LibraryRepository+Sync`), so the probe has to get cheaper the longer the
    /// server stays away. Five seconds is short enough that a server restarting
    /// while you watch feels instant; two minutes is a cost of nothing on a machine
    /// left open overnight.
    ///
    /// Pure, so the schedule can be checked without waiting for it.
    public static func retryDelay(attempt: Int) -> TimeInterval {
        let floor: TimeInterval = 5
        let ceiling: TimeInterval = 120
        guard attempt > 0 else { return floor }
        // Capped before the shift, or a large attempt count overflows the exponent
        // long before it reaches the ceiling.
        let steps = min(attempt, 8)
        return min(floor * pow(2, Double(steps)), ceiling)
    }
}
