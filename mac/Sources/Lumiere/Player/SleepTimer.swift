import Foundation

extension Notification.Name {
    /// The sleep timer ran out: stop and close the player.
    static let sleepTimerFired = Notification.Name("lumiere.sleepTimerFired")
}

/// "Stop after this episode", "stop in an hour".
///
/// Kept outside the player: the player is rebuilt for every episode, and a
/// timer set during one has to outlive it. One timer at a time, never
/// remembered — it is set for tonight.
@MainActor
enum SleepTimer {
    enum Mode: Equatable { case off, afterEpisode, at(Date) }

    private(set) static var mode: Mode = .off
    private static var task: Task<Void, Never>?

    /// 0 is after this episode, a positive number is minutes, anything else
    /// cancels.
    static func set(minutes: Int) {
        task?.cancel()
        task = nil
        switch minutes {
        case 0: mode = .afterEpisode
        case 1...: let when = Date().addingTimeInterval(Double(minutes) * 60)
            mode = .at(when)
            task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
                guard !Task.isCancelled else { return }
                mode = .off
                NotificationCenter.default.post(name: .sleepTimerFired, object: nil)
            }
        default: mode = .off
        }
    }

    /// True once, when an episode ends with "after this episode" set: the
    /// caller stops instead of going on, and the timer is spent.
    static func takeEndOfEpisode() -> Bool {
        guard mode == .afterEpisode else { return false }
        mode = .off
        return true
    }

    /// What the player says when it is set.
    static var description: String {
        switch mode {
        case .off: return "Sleep timer off"
        case .afterEpisode: return "Stopping after this one"
        case .at(let date): return "Stopping at " + date.formatted(date: .omitted, time: .shortened)
        }
    }
}
