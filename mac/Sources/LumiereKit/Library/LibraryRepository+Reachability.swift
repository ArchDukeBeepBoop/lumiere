import Foundation

/// Asking the one question offline mode needs answered: is the server back?
///
/// Deliberately not a new endpoint or a new client method. `userViews` is the
/// cheapest authenticated call this app already makes — a handful of rows, no
/// `Fields`, no recursion — and it is the same request `syncLibraries` opens with,
/// so a probe that succeeds is strong evidence the sync behind it will too. Adding
/// a separate `/System/Info/Public` ping would answer a different question: that
/// something is listening on the port, which an unauthenticated reverse proxy will
/// happily say while Jellyfin itself is still starting.
public extension LibraryRepository {

    /// Whether the server answered at all.
    ///
    /// "Answered" rather than "answered well", and the difference is the point. A
    /// 401 means the server is up and this session is stale — a real problem, but
    /// not one a reconnect probe can solve by asking again, so it must resolve as
    /// reachable and let the sync that follows report the actual refusal. Only a
    /// transport failure keeps the probe waiting.
    func isReachable() async -> Bool {
        do {
            _ = try await client.userViews()
            return true
        } catch {
            return !ConnectionState.isUnreachable(error)
        }
    }
}
