import Foundation

/// When to restart the server, and when to stop trying.
///
/// The first version stopped the server after a single missed probe and never
/// started it again. A probe misses exactly when the server is busiest — the
/// Lumiere app's launch, a dozen library syncs at once — so the moment the app
/// needed the server most was the moment this killed it, and the log said
/// "The network connection was lost" at launch after launch.
///
/// Kubernetes' liveness rules instead: several misses in a row before acting,
/// and acting means restarting. launchd's instead for crashes: restart, with a
/// growing pause, and give up when restarts come too fast to be anything but
/// a server that cannot run. Pure, so the policy is tested with a fake clock.
public struct Watchdog: Sendable {

    public enum Action: Equatable, Sendable {
        case none
        /// Restart after this pause.
        case restart(after: Duration)
        /// Too many restarts too quickly: leave it stopped and say so.
        case giveUp
    }

    public static let missesBeforeRestart = 3
    public static let restartsAllowed = 5
    public static let window: TimeInterval = 600

    private var misses = 0
    private var restarts: [Date] = []

    public init() {}

    /// One probe of a running server.
    public mutating func probed(answered: Bool, now: Date) -> Action {
        if answered {
            misses = 0
            return .none
        }
        misses += 1
        guard misses >= Self.missesBeforeRestart else { return .none }
        misses = 0
        return restart(now: now)
    }

    /// The server exited on its own.
    public mutating func crashed(now: Date) -> Action {
        misses = 0
        return restart(now: now)
    }

    private mutating func restart(now: Date) -> Action {
        restarts.removeAll { now.timeIntervalSince($0) > Self.window }
        guard restarts.count < Self.restartsAllowed else { return .giveUp }
        restarts.append(now)
        // 1, 2, 4, 8, 16 seconds: the first restart is nearly immediate, and a
        // server failing over and over is not hammered.
        let seconds = min(60, 1 << (restarts.count - 1))
        return .restart(after: .seconds(seconds))
    }
}
